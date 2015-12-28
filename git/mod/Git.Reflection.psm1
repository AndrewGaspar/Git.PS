
$commandCapture = "(?<command>[\w-\.]+)"

$shortParameterCapture = "(?<short>-\w)"
$longParameterCapture = "(?<long>--[\w-]+)"
$parameterCapture = "(?:(?:$shortParameterCapture(?:, $longParameterCapture)?)|$longParameterCapture)"
$argumentCapture = "(?:(?:<(?<argument>[\w-]+)>)|(?<argument>\.\.\.))"
$optCapture = "(?<optional_arg>\[=$argumentCapture\])"
$description = "(?<description>.*)"
$helpCapture = "$parameterCapture(?:(?: $argumentCapture)|$optCapture)?(?:\s+$description)?"

$usageCapture = "(?<git>git)(?<sub_commands>(?:(?: |-)$commandCapture)+)(?: (?<usage>.*))?"

$commandUsageCapture="^(?:(?:usage)|(?:   or)): $usageCapture$"

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

class GitUsage {
    [string]$CommandName
    [string]$Usage
}

function Read-GitCommandUsage {
    process {
        if($_ -match $commandUsageCapture)
        {
            New-Object GitUsage -Property @{
                CommandName = $Matches["command"]
                Usage = $Matches["usage"]
            }
        }
    }
}

function Get-GitCommandUsage {
    Param([string]$Name = "*")
    
    Get-GitCommandHelpMessage $Name | Read-GitCommandUsage
}

class GitSubCommands {
    [string]$CommandName
    [string[]]$SubCommands
    [string]$Usage
    [string]$Description
}

function Read-GitBisectCommandSubCommands {
    begin {
        $readDescription = $false
        $lastSubcommand = $null
    }
    
    process {
        if($_ -match "^$usageCapture$")
        {
            if($lastSubcommand) {
                $lastSubcommand
                $lastSubcommand = $null
                $readDescription = $false
            }
            
            $sub_commands = $Matches["sub_commands"].Trim().Split(' -');
            
            if($sub_commands.Count -lt 2)
            {
                continue;
            }
            
            $lastSubcommand = New-Object GitSubCommands -Property @{
                CommandName = $sub_commands[0]
                SubCommands = $sub_commands | Select-Object -Skip 1
            }
            
            $readDescription = $true
        } elseif ($readDescription)
        {
            $lastSubcommand.Description = $_.Trim()
            $readDescription = $false
        }
    }
    
    end {
        if($lastSubcommand) {
            $lastSubcommand
            $lastSubcommand = $null
            $readDescription = $false
        }
    }
}

function Get-GitBisectCommandSubCommands {
    Get-GitCommandHelpMessage "bisect" | Read-GitBisectCommandSubCommands
}

function Get-GitCommandSubCommands {
    Param([string]$Name="*")
    
    Get-GitCommandName $Name | 
        ForEach-Object {
            if($_ -eq "bisect") {
                Get-GitBisectCommandSubCommands
            }
        }
}

$nonHelpfulCommands = @("gui*", "citool", "remote-*", "sh-i18n--envsubst", "credential*")

function IsCommandNotHelpful {
    Param([string]$command)
    
    return !!($nonHelpfulCommands | Where-Object { $command -like $_ })
}

function Get-GitCommandHelpMessage {
    Param([string]$Name = "*")
    
    Get-GitCommandName $Name |
        Where-Object {
            !(IsCommandNotHelpful $_)
        } |
        ForEach-Object {
            git $_ -h 2>&1
        } | 
        ForEach-Object {
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

function Get-GitCommandParameter {
    Param([string]$Name = "*")
    
    Get-GitCommandHelpMessage $Name | Read-GitCommandParameter
}

class GitCommand
{
    [string]$Name
    [GitCommandParameter[]]$Parameters
    [GitUsage[]]$Usage
    [GitSubCommands[]]$SubCommands
}

function Get-GitCommandName
{
    Param([string]$Name = "*")
    
    git help -a 2>&1 | 
        ForEach-Object {
            if($_ -match "^  (?<first>$commandCapture)\s+(?<second>$commandCapture)(?:\s+(?<third>$commandCapture))?\s*$")
            {
                $Matches["first"]
                $Matches["second"]
                $Matches["third"] | ? { $_ }
            } 
        } |
        Where-Object {
            $_ -like $Name
        } | Sort-Object
}

function Get-GitCommand
{
    Param([string]$Name = "*")
    
    Get-GitCommandName $Name |
        ForEach-Object {
            if(IsCommandNotHelpful $_)
            {
                $parameters = @()
                $usage = @()
            }
            else
            {
                $helpMessage = Get-GitCommandHelpMessage $_
                $parameters = [GitCommandParameter[]]($helpMessage | Read-GitCommandParameter)
                $usage = [GitUsage[]]($helpMessage | Read-GitCommandUsage)
                $subCommands = [GitSubCommands[]](Get-GitCommandSubCommands $_)
            }
            
            [GitCommand]@{
                Name = $_
                Parameters = $parameters
                Usage = $usage
                SubCommands = $subCommands
            }
        }
}

function CompleteGitCommand {
    param($commandName,
        $parameterName,
        $wordToComplete,
        $commandAst,
        $fakeBoundParameter)
        
    Get-GitCommandName "$wordToComplete*" |
        ForEach-Object {
            New-CompletionResult $_ "Command: $_"
        }
}

Register-ArgumentCompleter `
    -CommandName @("Get-GitCommand", "Get-GitCommandName", "Get-GitCommandParameter", "Get-GitCommandHelpMessage", "Get-GitCommandUsage", "Get-GitCommandSubCommands") `
    -ParameterName Name `
    -Description "Provides command completion for git reflection commands" `
    -ScriptBlock $function:CompleteGitCommand

Set-Alias gith Get-GitCommandHelpMessage
