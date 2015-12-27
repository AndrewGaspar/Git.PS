class ParameterDescription {
    [string]$Name
    [string]$Alias
    [string]$Tooltip
    [string]$ArgumentType
    [bool]$IsArgumentOptional
}

class TabCompletionDescription {
    [string]$Command
    [TabCompletionDescription[]]$SubCommands
    [ParameterDescription[]]$Parameters
}

$Script:CompletionRegistrations = @{}

function Register-NativeTabCompletion {
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$True)]
        [TabCompletionDescription]$Description
    )
    
    $Script:CompletionRegistrations[$Description.command] = $Description
    
    Register-ArgumentCompleter `
        -CommandName $Description.Command `
        -Native `
        -ScriptBlock {
            Param(
                $wordToComplete,
                $commandAst,
                $cursor)
                
            $commandDescription = Get-NativeTabCompletion $commandAst.GetCommandName()
            
            foreach($subCommand in $commandDescription.SubCommands)
            {
                [System.Management.Automation.CompletionResult]::new(
                    $subCommand.Command,
                    $subCommand.Command,
                    "Command",
                    $subCommand.Command
                )
            }
        }
}

function ParseCompletionDescription {
    Param(
        [Parameter(
            Mandatory=$True, 
            ValueFromPipeline=$True,
            ValueFromPipelineByPropertyName)]
        [PSCustomObject]
        $Descriptions)

    $Descriptions | ForEach-Object {
        $completionDescription = [TabCompletionDescription]::new()
        
        $completionDescription.Command = $_.command
        if($_.sub_commands)
        {
            $completionDescription.SubCommands = $_.sub_commands | ForEach-Object {
                ParseCompletionDescription $_
            }
        }
        
        if($_.parameters)
        {
            $completionDescription.Parameters = $_.parameters | ForEach-Object {
                $parameterDescription = [ParameterDescription]::new()
                
                $parameterDescription.Name = $_.name
                $parameterDescription.Alias = $_.alias
                $parameterDescription.Tooltip = $_.tooltip
                $parameterDescription.ArgumentType = $_.argument_type
                $parameterDescription.IsArgumentOptional = $_.argument_optional
                
                $parameterDescription
            }
        }
        
        $completionDescription
    }
}

function Read-NativeTabCompletion {
    Param(
        [Parameter(Mandatory=$True, ValueFromPipeline=$True)]
        [string]$Path
    )
    
    Get-Content $Path | ConvertFrom-Json | ParseCompletionDescription 
}

function Get-NativeTabCompletion {
    Param(
        [string]$CommandName = "*"
    )
    
    $hash = $Script:CompletionRegistrations
    
    $hash.Keys | 
        Where-Object { $_ -like $CommandName } | 
        ForEach-Object { $hash[$_] }
}

