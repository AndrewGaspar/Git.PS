# [CmdletBinding()]
# Param([string]$preGenerationLocation, [string]$completionLocation)

function ParseGitHelpParameters 
{
    begin {
        $getDescription = $false
    }
    
    process {
        $_
    }
    
    end {
        
    }
}

function GetGitCommandParameters
{
    Param([string]$commandName)
    
    $argumentCapture = "\<(?<argument>\w+)\>"
    
    git $commandName -h | ForEach-Object {
        if($_ -match "^    (?<short>-\w)( ,(?<long>--\w+))?(( $argumentCapture)|(?<optional_arg>[=$argumentCapture]))?\w+$")
        {
            
        }
    }
}

function GetGitHelpParameters
{
    git 
}

function CompleteGitCompletionOptions
{
    Param([PSObject]$completionOptions)
    
    
}

$preGeneration = Get-Content $preGenerationLocation | ConvertFrom-Json

$preGeneration | ConvertTo-Json > "Git.Completion.json"