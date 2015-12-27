
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

$commandsWithNonStandardOutput = @{
    branch = @"
usage: git branch [<options>] [-r | -a] [--merged | --no-merged]
   or: git branch [<options>] [-l] [-f] <branch-name> [<start-point>]
   or: git branch [<options>] [-r] (-d | -D) <branch-name>...
   or: git branch [<options>] (-m | -M) [<old-branch>] <new-branch>

Generic options
    -v, --verbose         show hash and subject, give twice for upstream branch
    -q, --quiet           suppress informational messages
    -t, --track           set up tracking mode (see git-pull(1))
    --set-upstream        change upstream info
    -u, --set-upstream-to <upstream>
                          change the upstream info
    --unset-upstream      Unset the upstream info
    --color[=<when>]      use colored output
    -r, --remotes         act on remote-tracking branches
    --contains <commit>   print only branches that contain the commit
    --abbrev[=<n>]        use <n> digits to display SHA-1s

Specific git-branch actions:
    -a, --all             list both remote-tracking and local branches
    -d, --delete          delete fully merged branch
    -D                    delete branch (even if not merged)
    -m, --move            move/rename a branch and its reflog
    -M                    move/rename a branch, even if target exists
    --list                list branch names
    -l, --create-reflog   create the branch's reflog
    --edit-description    edit the description for the branch
    -f, --force           force creation, move/rename, deletion
    --no-merged <commit>  print only not merged branches
    --merged <commit>     print only merged branches
    --column[=<style>]    list branches in columns
"@
}

function Get-GitCommandHelpMessage
{
    Param([string]$CommandName)
    
    if($commandsWithNonStandardOutput[$CommandName])
    {
        $commandsWithNonStandardOutput[$CommandName]  -split "`n"
    }
    else
    {
        git $CommandName -h
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