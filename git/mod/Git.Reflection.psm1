
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

function Read-GitCommandParameters 
{
    begin {
        $getDescription = $false
    }
    
    process {
        if($_ -match "^    $helpCapture$")
        {
            $getDescription = !$Matches["description"]
            
            $lastSeen = [GitCommandParameter]@{
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

function Get-GitCommandParameters
{
    Param([string]$CommandName)
    
    git $CommandName -h 2>&1 | Read-GitCommandParameters
}

function GetGitHelpParameters
{
    git 
}

function CompleteGitCompletionOptions
{
    Param([PSObject]$completionOptions)
    
    
}