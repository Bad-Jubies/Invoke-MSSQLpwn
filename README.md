# Invoke-MSSQLpwn

Invoke-MSSQLpwn is a PowerShell tool that attempts to gain code execution on MSSQL servers in an Active Directory environment.

## Usage

| Parameter | Description |
|---|---|
| `Enumerate` | This will find MSSQL service principal names within the current domain, attempt to authenticate as the current user, enumerate permissions on the server, and find linked servers. |
| `Target` | Specifies the MSSQL server to be connected to |
| `Link` | Specifies a linked server on the target server to connect to |
| `Impersonate` | Specifies a login to be impersonated on the target server |
| `LinkImpersonate` | Specifies a login to be impersonated on the linked server |
| `Command` | Cmd command to be executed |
| `Mode` | Specifies the how code execution is obtained. This can be set to 1 or 2. Mode 1 is the default and uses xp_cmdshell. Mode 2 uses a custom ole automation procedure |
| `Relay` | Specifies the attacking server to be connected to for an SMB relay attack. This uses the xp_dirtree procedure to connect to the SMB share. |
| `database` | Specifies the database to be used in the connection string. The default is master. |

![Example](https://user-images.githubusercontent.com/62299138/114249179-7d6a6680-995f-11eb-91fa-f8628b4828a8.png)
