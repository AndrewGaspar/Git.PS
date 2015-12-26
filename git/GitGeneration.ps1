Param([string]$preGenerationLocation, [string]$completionLocation)

$scriptPath = Split-Path $PSCommandPath

Import-Module "$scriptPath\mod\Git.Reflection.psm1"

$preGeneration = Get-Content $preGenerationLocation | ConvertFrom-Json

$sub_commands = & {
    $preGeneration.sub_commands
    
    Get-GitCommand | ForEach-Object {
        $parameters = $_.Parameters | ForEach-Object {
            if($_.LongParameter)
            {
                $parameter = $_.LongParameter
            }
            else
            {
                $parameter = $_.ShortParameter
            }
            
            $obj = New-Object PSCustomObject -Property @{
                name = $parameter
                tooltip = $_.Description
            }
            
            if($_.LongParameter -and $_.ShortParameter)
            {
                $obj | Add-Member -NotePropertyName alias -NotePropertyValue $_.ShortParameter
            }
            
            if($_.ArgumentName)
            {
                $obj | Add-Member -NotePropertyName argument_type -NotePropertyValue $_.ArgumentName
                
                if($_.IsArgumentOptional)
                {
                    $obj | Add-Member -NotePropertyName argument_optional -NotePropertyValue $_.IsArgumentOptional
                }
            }
            
            $obj
        }
        
        New-Object PSCustomObject -Property @{
            command = $_.Name
            parameters = $parameters
        }
    }
} | Where-Object {
    $_
}

if(-not $preGeneration.sub_commands)
{
    Add-Member -InputObject $preGeneration -NotePropertyName "sub_commands" -NotePropertyValue @()
}

$preGeneration.sub_commands = $sub_commands

$preGeneration | ConvertTo-Json -Depth 10 | Out-File "Git.Completion.json" -Encoding utf8