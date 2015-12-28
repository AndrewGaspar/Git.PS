function Test-IsAdmin {
    ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
            [Security.Principal.WindowsBuiltInRole] "Administrator")
}

if(Test-IsAdmin)
{
    $userScope = "Machine"
}
else
{
    $userScope = "user"
}

$repoRoot = Split-Path $PSCommandPath

$gitPSPath = Join-Path $repoRoot "mod"

foreach($scope in @("Process", $userScope))
{
    $path = [System.Environment]::GetEnvironmentVariable("PSModulePath", $scope)
    if(!$path)
    {
        $path = ""
    }
    
    if($path -and ($path[$path.Length - 1] -ne ';'))
    {
        $semicolon = ';'
    }
    else
    {
        $semicolon = ''
    }
    
    [System.Environment]::SetEnvironmentVariable("PSModulePath", "$path$semicolon$gitPSPath", $scope)
}