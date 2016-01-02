
$commandCapture = "(?<command>\w[\w-\.]*)"

function CommandGroupCapture([string]$captureNumber)
{
    "(?:(?<first_command>$commandCapture)(?<rest_commands>(\|$commandCapture)$captureNumber))"
}

$commandGroupCaptureAtLeastTwo = CommandGroupCapture "+"
$commandGroupCapture = CommandGroupCapture "*"

$shortParameterCapture = "(?<short>-\w)"
$longParameterCapture = "(?<long>--[\w-]+)"
$parameterCapture = "(?:(?:$shortParameterCapture(?:, $longParameterCapture)?)|$longParameterCapture)"
$argumentCapture = "(?:(?:<(?<argument>[\w-]+)>)|(?<argument>\.\.\.))"
$optCapture = "(?<optional_arg>\[=$argumentCapture\])"
$parameterArgumentCapture = "(?:(?<argumennt_capture>(?: $argumentCapture)|$optCapture)?)"
$description = "(?<description>.*)"
$helpCapture = "$parameterCapture$parameterArgumentCapture(?:\s+$description)?"

$usageParameterCapture = "(?<usage_capture>(?<usage_parameter>$shortParameterCapture|$longParameterCapture)$parameterArgumentCapture)"
$orUsageParameterCapture = "(?:(?<or_first_parameter>$usageParameterCapture)(?<or_rest_parameter>(?: \| $usageParameterCapture)*))"
$optionalUsageParameterCapture = "(?<optional_usage_parameter>\[$orUsageParameterCapture\])"
$subCommandNameCapture = "^($optionalUsageParameterCapture )?$commandCapture"
$multipleOptionalUsageParameterCapture = "(?:(?<first_optional_parameter>$optionalUsageParameterCapture)(?<rest_optional>(?: $optionalUsageParameterCapture)*))"

$usageCapture = "(?<usage>.*)"

$gitUsageCapture = "(?<git>git)(?<sub_commands>(?:(?: |-)$commandCapture)+)(?: $usageCapture)?"

$gitCommandUsageCapture="^(?:(?:usage)|(?:   or)): $gitUsageCapture$"

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
    [string]$Name
    [string]$Usage
}

function Read-GitCommandUsage {
    process {
        if($_ -match $gitCommandUsageCapture)
        {
            $subCommands = $Matches["sub_commands"].Trim().Split(' ')

            if($subCommands[0].StartsWith('-')) {
                $subCommands[0] = $subCommands.Substring(1)
            }
            
            New-Object GitUsage -Property @{
                Name = $subCommands[0]
                Usage = "$(($subCommands | Select-Object -Skip 1) -join " ") $($Matches["usage"])".Trim()
            }
        }
    }
}

function Get-GitCommandUsage {
    Param([string]$Name = "*")
    
    Get-GitCommandHelpMessage $Name | Read-GitCommandUsage
}

class GitCommand
{
    [string]$Name
    [string]$ParentName
    [GitCommandParameter[]]$Parameters
    [GitUsage[]]$Usage
    [GitCommand[]]$SubCommands
    [GitAlias[]]$AliasedTo
    [string]$Description
}

function Read-GitBisectCommandSubCommands {
    begin {
        $readDescription = $false
        $lastSubcommand = $null
    }
    
    process {
        if($_ -match "^$gitUsageCapture$")
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
            
            $name = $sub_commands[1]
            
            $lastSubcommand = New-Object GitCommand -Property @{
                Name = $name
            }
            
            if($Matches["usage"])
            {
                $lastSubcommand.Usage = New-Object GitUsage -Property @{
                    Name = $name
                    Usage = "$(($sub_commands | Select-Object -Skip 2) -join " ") $($Matches["usage"])"
                }
            }
            
            $readDescription = $true
        } elseif ($readDescription) {
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

class GitSubCommandName {
    [string]$Name
    [string]$SubCommandName
}

function Read-GitCommandSubCommandName {
    $input | Read-GitCommandUsage |
        ForEach-Object {
            & {
                if($_.Usage -match $subCommandNameCapture) {
                    New-Object GitSubCommandName -Property @{
                        Name = $_.Name
                        SubCommandName = $Matches["command"]
                    }
                } elseif ($_.Usage -match "^\[$commandGroupCaptureAtLeastTwo\]") {
                    do {
                        New-Object GitSubCommandName -Property @{
                            Name = $_.Name
                            SubCommandName = $Matches["first_command"]
                        }
                        
                        if($Matches["rest_commands"])
                        {
                            $rest_commands = $Matches["rest_commands"].Substring(1)
                        } else {
                            break
                        }
                    } while($rest_commands -match "$commandGroupCapture")
                }
            }
        } | 
        Group-Object -Property Name |
        ForEach-Object {
            $_.Group | 
                Sort-Object SubCommandName -Unique
        }
}

function Get-GitCommandSubCommandName {
    Param(
        [string]$Name = "*",
        [string]$SubCommandName = "*")
        
    Get-GitCommandName $Name |
        ForEach-Object {
            Get-GitCommandHelpMessage $_ | 
                Read-GitCommandSubCommandName |
                Where-Object { 
                    $_.SubCommandName -like $SubCommandName 
                }
        }
}

class GitSubCommandUsage {
    [string]$Name
    [string]$SubCommandName
    [string]$Usage
}

function Read-GitCommandSubCommandUsage {
    Param(
        [string]$SubCommandName = "*")
    
    # make copy of input
    $in = $input | ForEach-Object { $_ }

    $subCommandNames = $in | Read-GitCommandSubCommandName | Where-Object { $_.SubCommandName -like $SubCommandName }
    
    $subCommandNames | ForEach-Object {
        $self = $_
        
        $in | ForEach-Object {
            if($_ -match "git $($self.Name) ($optionalUsageParameterCapture )?$($self.SubCommandName)( $usageCapture)?") {
                $obj = New-Object GitSubCommandUsage -Property @{
                    Name = $self.Name
                    SubCommandName = $self.SubCommandName
                    Usage = $Matches["usage"]
                }

                if($Matches["usage"]) {
                    $obj.Usage = $Matches["usage"].Trim()
                }

                $obj
            }
        }
    }
}

function Get-GitCommandSubCommandUsage {
    Param(
        [string]$Name="*",
        [string]$SubCommandName = "*")
    
    Get-GitCommandName $Name |
        ForEach-Object {
            Get-GitCommandHelpMessage $_ | 
                Read-GitCommandSubCommandUsage |
                Where-Object { 
                    $_.SubCommandName -like $SubCommandName 
                }
        }
}

function Read-GitSubCommand {
    Param([string]$Name="*")
    
    $input | Read-GitCommandSubCommandUsage $Name | 
        Group-Object -Property SubCommandName |
        ForEach-Object {
            $group = $_
            
            New-Object GitCommand -Property @{
                Name = $group.Name
                ParentName = $group.Group[0].Name
                Usage = [GitUsage[]]($group.Group | ForEach-Object {
                    New-Object GitUsage -Property @{
                        Name = $group.Name
                        Usage = $_.Usage
                    }
                })
            }
        }
}

function Get-GitSubCommand {
    Param(
        [string]$Name="*",
        [string]$ParentName="*")
        
    Get-GitCommandName $ParentName |
        ForEach-Object {
            Get-GitCommandHelpMessage $_ | Read-GitSubCommand $Name
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
    [string]$Name
    [string]$Alias
}

$ignoreAliasCommands = @("log", "show")

function Read-GitCommandAliased {
    Param([string]$Name)
    
    if($ignoreAliasCommands | Where-Object {
        $Name -match $_
    })
    {
        return;
    }
    
    $input | Read-GitCommandUsage | ForEach-Object {
        if($_.Name -ne $Name) {
            New-Object GitAlias -Property @{
                Name = $_.Name
                Alias = $Name
            }
        }
    }
}

function Get-GitCommandAliased {
    Param([string]$Name = "*")
    
    Get-GitCommandName $Name | ForEach-Object {
        Get-GitCommandHelpMessage $_ | Read-GitCommandAliased $_
    }
}

function Get-GitCommandAlias {
    Param([string]$Name = "*")
    
    Get-GitCommandAliased * | Where-Object { $_.Name -match $Name }
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
            if(IsCommandNotHelpful $_) {
                $parameters = @()
                $usage = @()
                $subCommands = @()
                $aliasTo = @()
            } else {
                $helpMessage = Get-GitCommandHelpMessage $_
                
                $parameters = [GitCommandParameter[]]($helpMessage | Read-GitCommandParameter)
                $usage = [GitUsage[]]($helpMessage | Read-GitCommandUsage)
                $subCommands = [GitCommand[]]($helpMessage | Read-GitSubCommand)
                $aliasTo = [GitAlias[]]($helpMessage | Read-GitCommandAliased $_)
            }
            
            [GitCommand]@{
                Name = $_
                Parameters = $parameters
                Usage = $usage
                SubCommands = $subCommands
                AliasedTo = $aliasTo
            }
        }
}

function Read-GitUsage {
    foreach($line in $input)
    {
        if($usage -eq "done") {
            return;
        } elseif(!$usage) {
            if(!($line -match "^usage: git (?<rest>.*)$"))
            {
                return $null
            }
            
            $usage = $Matches["rest"].Trim()
        } elseif (!($line.Trim())) {
            $usage
            $usage = "done"
            return;
        } else {
            $usage = "$usage $($line.Trim())"
        }
    }
}

function Get-GitUsage {
    git | Read-GitUsage
}

function GitCompletion_NewResult($CompletionText, $ToolTip) {
    if(Get-Module TabExpansionPlusPlus)
    {
        New-CompletionResult $CompletionText $ToolTip
    }
    else
    {
        [System.Management.Automation.CompletionResult]::new($CompletionText, $CompletionText, "ParameterValue", $ToolTip)
    }
}

function GitCompletion_GitCommand {
    param($commandName,
        $parameterName,
        $wordToComplete,
        $commandAst,
        $fakeBoundParameter)
        
    Get-GitCommandName "$wordToComplete*" |
        ForEach-Object {
            GitCompletion_NewResult $_ "Command: $_"
        }
}

function GitCompletion_GitCommandSubCommand {
    param($commandName,
        $parameterName,
        $wordToComplete,
        $commandAst,
        $fakeBoundParameter)
        
    Get-GitCommandSubCommandName $fakeBoundParameter.Name "$wordToComplete*" |
        ForEach-Object {
            GitCompletion_NewResult $_.SubCommandName "Command: $($_.Name), SubCommand: $($_.SubCommandName)"
        }
}

function GitCompletion_GitSubCommandName {
    param($commandName,
        $parameterName,
        $wordToComplete,
        $commandAst,
        $fakeBoundParameter)
        
    Get-GitCommandSubCommandName $fakeBoundParameter.ParentName "$wordToComplete*" |
        ForEach-Object {
            GitCompletion_NewResult $_.SubCommandName "Command: $($_.Name), SubCommand: $($_.SubCommandName)"
        }
}

$completionCommands = Get-Command "Get-GitCommand*"
$commandSubCommandCompletionCommands = Get-Command "Get-GitCommandSubCommand*"
$subCommandCompletion = Get-Command "Get-GitSubCommand*"

function RegisterCompleter($CommandName, $ParameterName, $Description, $ScriptBlock) {
    if(Get-Module TabExpansionPlusPlus)
    {
        TabExpansionPlusPlus\Register-ArgumentCompleter `
            -CommandName $CommandName `
            -ParameterName $ParameterName `
            -Description $Description `
            -ScriptBlock $ScriptBlock
    }
    else
    {
        Microsoft.PowerShell.Core\Register-ArgumentCompleter `
            -CommandName $CommandName `
            -ParameterName $ParameterName `
            -ScriptBlock $ScriptBlock
    }
}

RegisterCompleter `
    -CommandName $completionCommands `
    -ParameterName Name `
    -Description "Provides command completion for git reflection commands" `
    -ScriptBlock $function:GitCompletion_GitCommand
    
RegisterCompleter `
    -CommandName $commandSubCommandCompletionCommands `
    -ParameterName SubCommandName `
    -Description "Provides sub-command completion for git reflection commands" `
    -ScriptBlock $function:GitCompletion_GitCommandSubCommand
    
RegisterCompleter `
    -CommandName $subCommandCompletion `
    -ParameterName ParentName `
    -Description "Provides command completion for sub-command ParentName parameters" `
    -ScriptBlock $function:GitCompletion_GitCommand
    
RegisterCompleter `
    -CommandName $subCommandCompletion `
    -ParameterName Name `
    -Description "Provides command completion for sub-command Name parameters" `
    -ScriptBlock $function:GitCompletion_GitSubCommandName

Set-Alias gith Get-GitCommandHelpMessage
