
$commandName = "(?:[\w-\.]+)"
$shortParameterCapture = "(?<short>-\w)"
$longParameterCapture = "(?<long>--[\w-]+)"
$parameterCapture = "(?:(?:$shortParameterCapture(?:, $longParameterCapture)?)|$longParameterCapture)"
$argumentCapture = "<(?<argument>[\w-]+)>"
$optCapture = "(?<optional_arg>\[=$argumentCapture\])"
$description = "(?<description>.*)"
$helpCapture = "$parameterCapture(?:(?: $argumentCapture)|$optCapture)?(?:\s+$description)?"

$global:debugHelp = $helpCapture

class GitCommandParameter {
    [string]$ShortParameter
    [string]$LongParameter
    [string]$ArgumentName
    [bool]$IsArgumentOptional
    [string]$Description
}

function Read-GitCommandParameter 
{
    begin {
        $getDescription = $false
    }
    
    process {
        if($_ -match "^    $helpCapture$")
        {
            $getDescription = !$Matches["description"]
            
            $lastSeen = New-Object GitCommandParameter -Property @{
                ShortParameter=$Matches["short"]
                LongParameter=$Matches["long"]
                ArgumentName=$Matches["argument"]
                IsArgumentOptional= if($Matches["argument"]) { !!$Matches["optional_arg"] } else { $True }
                Description = $Matches["description"]
            }
            
            if(!$getDescription)
            {
                $lastSeen
            }
        } 
        elseif ($getDescription)
        {
            $getDescription = $false;
            
            $lastSeen.Description = $_.Trim();
            
            $lastSeen
            
            $lastSeen = $null
        }
    }
    
    end {
        
        if($lastSeen)
        {
            $lastSeen
        }
    }
    
}

function Get-GitCommandHelpMessage
{
    Param([string]$CommandName)
    
    git $CommandName -h 2>&1 | ForEach-Object {
        if($_ -is [System.Management.Automation.ErrorRecord])
        {
            $_.Exception.Message -split "`n";
        }
        else
        {
            $_
        }
    }
}

function Get-GitCommandParameter
{
    Param([string]$CommandName)
    
    Get-GitCommandHelpMessage $CommandName | Read-GitCommandParameter
}

class GitCommand
{
    [string]$Name
    [GitCommandParameter[]]$Parameters
}

$nonHelpfulCommands = @("gui*", "citool", "remote-*", "sh-i18n--envsubst", "credential*")

function IsCommandNotHelpful {
    Param([string]$command)
    
    return !!($nonHelpfulCommands | Where-Object { $command -like $_ })
}

function Get-GitCommand
{
    Param([string]$Name = "*")
    
    git help -a 2>&1 | 
        ForEach-Object {
            if($_ -match "^  (?<first>$commandName)\s+(?<second>$commandName)(?:\s+(?<third>$commandName))?\s*$")
            {
                $Matches["first"]
                $Matches["second"]
                $Matches["third"] | ? { $_ }
            } 
        } |
        Where-Object {
            $_ -like $Name
        } |
        ForEach-Object {
            if(!(IsCommandNotHelpful $_))
            {
                $parameters = [GitCommandParameter[]](Get-GitCommandParameter $_)
            }
            else
            {
                $parameters = @()
            }
            
            [GitCommand]@{
                Name = $_
                Parameters = $parameters
            }
        }
}

function CompleteGitCompletionOptions
{
    Param([PSObject]$completionOptions)
    
    
}