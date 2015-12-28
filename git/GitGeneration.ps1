Param([string]$preGenerationLocation, [string]$completionLocation)

$scriptPath = Split-Path $PSCommandPath

if(!$preGenerationLocation)
{
    $preGenerationLocation = Join-Path $scriptPath "Git.PreGeneration.json"
}

if(!$completionLocation)
{
    $completionLocation = Join-Path $scriptPath "Git.Completion.json"
}

Import-Module "$scriptPath\mod\Git.Reflection.psm1"

$preGeneration = Get-Content $preGenerationLocation | ConvertFrom-Json

function TransformGitCommand($gitCommand)
{
    $command_obj = New-Object PSCustomObject -Property @{
        command = $gitCommand.Name
    }
    
    if($gitCommand.AliasedTo)
    {
        $command_obj | Add-Member -NotePropertyName aliased_to -NotePropertyValue $gitCommand.AliasedTo.Name
    }
    else
    {
        $parameters = $gitCommand.Parameters |
            Where-Object {
                $_
            } |
            ForEach-Object {
                if($_.LongParameter)
                {
                    $parameter = $_.LongParameter
                }
                else
                {
                    $parameter = $_.ShortParameter
                }
                
                $parameter_obj = New-Object PSCustomObject -Property @{
                    name = $parameter
                }
                
                if($_.Description)
                {
                    $parameter_obj | Add-Member -NotePropertyName tooltip -NotePropertyValue $_.Description
                }
                
                if($_.LongParameter -and $_.ShortParameter)
                {
                    $parameter_obj | Add-Member -NotePropertyName alias -NotePropertyValue $_.ShortParameter
                }
                
                if($_.ArgumentName)
                {
                    $parameter_obj | Add-Member -NotePropertyName argument_type -NotePropertyValue $_.ArgumentName
                    
                    if($_.IsArgumentOptional)
                    {
                        $parameter_obj | Add-Member -NotePropertyName argument_optional -NotePropertyValue $_.IsArgumentOptional
                    }
                }
                
                $parameter_obj
            }
            
        if($parameters)
        {
            $command_obj | Add-Member -NotePropertyName parameters -NotePropertyValue $parameters
        }
    }
    
    $command_obj
}

$sub_commands = Get-GitCommand | 
    ForEach-Object {
        TransformGitCommand $_
    }
    
$sub_commands = & {
    $sub_commands
    
    foreach($pre_described_command in $preGeneration.sub_commands)
    {
        $sub_command = $sub_commands | 
            Where-Object { $_.command -eq $pre_described_command.command } | 
            Select-Object -First 1
        if($sub_command)
        {
            foreach($key in $pre_described_command.Keys) 
            {
                $sub_command[$key] = $pre_described_command[$key]
            }
        }
        else
        {
            $pre_described_command
        }
    }
} | Sort-Object -Property command

if(-not $preGeneration.sub_commands)
{
    Add-Member -InputObject $preGeneration -NotePropertyName "sub_commands" -NotePropertyValue @()
}

$preGeneration.sub_commands = $sub_commands

$preGeneration | ConvertTo-Json -Depth 10 | Out-File $completionLocation -Encoding utf8