
$commandCapture = "(?<command>\w[\w-\.]*)"

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
        if($_ -match "^    $helpCapture$") {
            if($lastSeen) {
                $lastSeen
                $lastSeen = $null
            }
            
            $getDescription = !$Matches["description"]
            
            $lastSeen = New-Object GitCommandParameter -Property @{
                ShortParameter=$Matches["short"]
                LongParameter=$Matches["long"]
                ArgumentName=$Matches["argument"]
                IsArgumentOptional= if($Matches["argument"]) { !!$Matches["optional_arg"] } else { $True }
                Description = $Matches["description"]
            }
        } elseif(!$_) {
            $getDescription = $false
        } elseif(!($_ -match "^ {26}")) {
            $getDescription = $false
        } elseif ($getDescription) {
            
            if($lastSeen.Description) {
                $lastSeen.Description += " $($_.Trim())"
            } else {
                $lastSeen.Description = $_.Trim();
            }
        }
    }
    
    end {
        if($lastSeen) {
            $lastSeen
            $lastSeen = $null
        }
    }
}

function Get-GitCommandParameter {
    Param([string]$Name = "*")
    
    Get-GitCommandHelpMessage $Name | Read-GitCommandParameter
}

class GitUsage {
    [string]$CommandName
    [string]$Usage
}

function Read-GitCommandUsage {
    process {
        if($_ -match $commandUsageCapture)
        {
            $subCommands = $Matches["sub_commands"].Trim().Split(' ')
            
            New-Object GitUsage -Property @{
                CommandName = $subCommands[0]
                Usage = "$(($subCommands | Select-Object -Skip 1) -join " ") $($Matches["usage"])".Trim()
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
            
            $sub_commands = $Matches["sub_commands"].Trim().Split(' ');
            
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
            else
            {
                Get-GitCommandUsage $_ | ForEach-Object {
                    if($_.Usage -match "^$commandCapture") {
                        $command = $Matches["command"]
                        
                        New-Object GitSubCommands -Property @{
                            CommandName = $_.CommandName
                            SubCommands = $command
                            Usage = $_.Usage.Substring($command.Length).Trim()
                        }
                    }
                }
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

class GitAlias {
    [string]$CommandName
    [string]$Alias
}

function Read-GitCommandAliased {
    Param([string]$Name)
    
    $input | Read-GitCommandUsage | ForEach-Object {
        if($_.CommandName -ne $Name) {
            New-Object GitAlias -Property @{
                CommandName = $_.CommandName
                Alias = $Name
            }
        }
    } | Select-Object -Unique
}

function Get-GitCommandAliased {
    Param([string]$Name = "*")
    
    Get-GitCommandName $Name | ForEach-Object {
        Get-GitCommandHelpMessage $_ | Read-GitCommandAliased $_
    }
}

function Get-GitCommandAlias {
    Param([string]$Name = "*")
    
    Get-GitCommandAliased * | Where-Object { $_.CommandName -match $Name }
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
    
    if(!$Name.Contains('*')) {
        return $Name
    }
    
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
    -CommandName @("Get-GitCommand", "Get-GitCommandName", "Get-GitCommandParameter", "Get-GitCommandHelpMessage", "Get-GitCommandUsage", "Get-GitCommandSubCommands", "Get-GitCommandAliased", "Get-GitCommandAlias") `
    -ParameterName Name `
    -Description "Provides command completion for git reflection commands" `
    -ScriptBlock $function:CompleteGitCommand

Set-Alias gith Get-GitCommandHelpMessage
