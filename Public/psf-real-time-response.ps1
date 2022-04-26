function Get-FalconQueue {
<#
.SYNOPSIS
Create a report of Real-time Response commands in the offline queue
.DESCRIPTION
Requires 'Real Time Response: Read', 'Real Time Response: Write' and 'Real Time Response (Admin): Write'.

Creates a CSV of pending Real-time Response commands and their related session information. By default, sessions
within the offline queue expire 7 days after creation. Sessions can have additional commands appended to them to
extend their expiration time.

Additional host information can be appended to the results using the 'Include' parameter.
.PARAMETER Days
Days worth of results to retrieve [default: 7]
.PARAMETER Include
Include additional properties
.LINK
https://github.com/crowdstrike/psfalcon/wiki/Real-time-Response
#>
    [CmdletBinding()]
    param(
        [Parameter(Position=1)]
        [int32]$Days,
        [Parameter(Position=2)]
        [ValidateSet('agent_version','cid','external_ip','first_seen','host_hidden_status','hostname',
            'last_seen','local_ip','mac_address','os_build','os_version','platform_name','product_type',
            'product_type_desc','reduced_functionality_mode','serial_number','system_manufacturer',
            'system_product_name','tags',IgnoreCase=$false)]
        [string[]]$Include
    )
    begin {
        $Days = if ($PSBoundParameters.Days) { $PSBoundParameters.Days } else { 7 }
        # Properties to capture from request results
        $Select = @{
            Session = @('aid','user_id','user_uuid','id','created_at','deleted_at','status')
            Command = @('stdout','stderr','complete')
        }
        # Define output path
        $OutputFile = Join-Path (Get-Location).Path "FalconQueue_$(Get-Date -Format FileDateTime).csv"
    }
    process {
        try {
            $SessionParam = @{
                Filter = "(deleted_at:null+commands_queued:1),(created_at:>'last $Days days'+commands_queued:1)"
                Detailed = $true
                All = $true
            }
            $Sessions = Get-FalconSession @SessionParam | Select-Object id,device_id
            if (-not $Sessions) { throw "No queued Real-time Response sessions available." }
            Write-Host "[Get-FalconQueue] Found $(($Sessions | Measure-Object).Count) queued sessions..."
            [array]$HostInfo = if ($PSBoundParameters.Include) {
                # Capture host information for eventual output
                $Sessions.device_id | Get-FalconHost | Select-Object @($PSBoundParameters.Include + 'device_id')
            }
            foreach ($Session in ($Sessions.id | Get-FalconSession -Queue)) {
                Write-Host "[Get-FalconQueue] Retrieved command detail for $($Session.id)..."
                @($Session.Commands).foreach{
                    # Create output for each individual command in queued session
                    $Obj = [PSCustomObject]@{}
                    @($Session | Select-Object $Select.Session).foreach{
                        @($_.PSObject.Properties).foreach{
                            # Add session properties with 'session' prefix
                            $Name = if ($_.Name -match '^(id|(created|deleted|updated)_at|status)$') {
                                "session_$($_.Name)"
                            } else {
                                $_.Name
                            }
                            Set-Property $Obj $Name $_.Value
                        }
                    }
                    @($_.PSObject.Properties).foreach{
                        # Add command properties
                        $Name = if ($_.Name -match '^((created|deleted|updated)_at|status)$') {
                            "command_$($_.Name)"
                        } else {
                            $_.Name
                        }
                        Set-Property $Obj $Name $_.Value
                    }
                    if ($Obj.command_status -eq 'FINISHED') {
                        # Update command properties with results
                        Write-Host "[Get-FalconQueue] Retrieving command result for cloud_request_id '$(
                            $Obj.cloud_request_id)'..."
                        $ConfirmCmd = Get-RtrCommand $Obj.base_command -ConfirmCommand
                        @($Obj.cloud_request_id | & $ConfirmCmd -EA 4 | Select-Object $Select.Command).foreach{
                            @($_.PSObject.Properties).foreach{ Set-Property $Obj "command_$($_.Name)" $_.Value }
                        }
                    } else {
                        @('command_complete','command_stdout','command_stderr').foreach{
                            # Add empty command output
                            $Value = if ($_ -eq 'command_complete') { $false } else { $null }
                            Set-Property $Obj $_ $Value
                        }
                    }
                    if ($PSBoundParameters.Include -and $HostInfo) {
                        @($HostInfo.Where({ $_.device_id -eq $Obj.aid })).foreach{
                            @($_.PSObject.Properties.Where({ $_.Name -ne 'device_id' })).foreach{
                                # Add 'Include' properties
                                Set-Property $Obj $_.Name $_.Value
                            }
                        }
                    }
                    try { $Obj | Export-Csv $OutputFile -NoTypeInformation -Append } catch { $Obj }
                }
            }
        } catch {
            throw $_
        } finally {
            if (Test-Path $OutputFile) { Get-ChildItem $OutputFile | Select-Object FullName,Length,LastWriteTime }
        }
    }
}
function Invoke-FalconDeploy {
<#
.SYNOPSIS
Deploy and run an executable using Real-time Response
.DESCRIPTION
Requires 'Hosts: Read', 'Real Time Response (Admin): Write'.

'Put' files will be checked for identical file names, and if any are found, the Sha256 hash values will be
compared between your local and cloud files. If they are different, a prompt will appear asking which file to use.

After ensuring that the 'Put' file is available, a Real-time Response session will be started for the designated
host(s) (or members of the Host Group), 'mkdir' will create a folder ('FalconDeploy_<FileDateTime>') within the
appropriate temporary folder (\Windows\Temp or /tmp), 'cd' will navigate to the new folder, and the target file or
archive will be 'put' into that folder. If the target is an archive, it will be extracted, and the designated
'Run' file will be executed. If the target is a file, it will be 'run'.

Details of each step will be output to a CSV file in your current directory.
.PARAMETER File
Name of a 'CloudFile' or path to a local executable to upload
.PARAMETER Archive
Name of a 'CloudFile' or path to a local archive to upload
.PARAMETER Run
Name of the file to run once extracted from the target archive
.PARAMETER Argument
Arguments to include when running the executable
.PARAMETER Timeout
Length of time to wait for a result, in seconds
.PARAMETER QueueOffline
Add non-responsive Hosts to the offline queue
.PARAMETER GroupId
Host group identifier
.PARAMETER HostId
Host identifier
.LINK
https://github.com/crowdstrike/psfalcon/wiki/Real-time-Response
#>
    [CmdletBinding(DefaultParameterSetName='HostId_File')]
    param(
        [Parameter(ParameterSetName='HostId_File',Mandatory,Position=1)]
        [Parameter(ParameterSetName='GroupId_File',Mandatory,Position=1)]
        [ValidateScript({
            if (Test-Path $_ -PathType Leaf) {
                $true
            } else {
                $FileName = [System.IO.Path]::GetFileName($_)
                if (Get-FalconPutFile -Filter "name:['$FileName']") {
                    $true
                } else {
                    throw "Cannot find path '$_' because it does not exist or is a directory."
                }
            }
        })]
        [Alias('Path','FullName')]
        [string]$File,
        [Parameter(ParameterSetName='HostId_Archive',Mandatory)]
        [Parameter(ParameterSetName='GroupId_Archive',Mandatory)]
        [ValidateScript({
            if ($_ -match '\.zip$') {
                if (Test-Path $_ -PathType Leaf) {
                    $true
                } else {
                    $FileName = [System.IO.Path]::GetFileName($_)
                    if (Get-FalconPutFile -Filter "name:['$FileName']") {
                        $true
                    } else {
                        throw "Cannot find path '$_' because it does not exist or is a directory."
                    }
                }
            } else {
                throw "'$_' does not match expected file extension."
            }
        })]
        [string]$Archive,
        [Parameter(ParameterSetName='HostId_Archive',Mandatory,Position=2)]
        [Parameter(ParameterSetName='GroupId_Archive',Mandatory,Position=2)]
        [string]$Run,
        [Parameter(ParameterSetName='HostId_File',Position=2)]
        [Parameter(ParameterSetName='GroupId_File',Position=2)]
        [Parameter(ParameterSetName='HostId_Archive',Position=3)]
        [Parameter(ParameterSetName='GroupId_Archive',Position=3)]
        [Alias('Arguments')]
        [string]$Argument,
        [Parameter(ParameterSetName='HostId_File',Position=3)]
        [Parameter(ParameterSetName='GroupId_File',Position=3)]
        [Parameter(ParameterSetName='HostId_Archive',Position=4)]
        [Parameter(ParameterSetName='GroupId_Archive',Position=4)]
        [ValidateRange(1,600)]
        [int32]$Timeout,
        [Parameter(ParameterSetName='HostId_File',Position=4)]
        [Parameter(ParameterSetName='GroupId_File',Position=4)]
        [Parameter(ParameterSetName='HostId_Archive',Position=5)]
        [Parameter(ParameterSetName='GroupId_Archive',Position=5)]
        [boolean]$QueueOffline,
        [Parameter(ParameterSetName='GroupId_File',Mandatory,ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName='GroupId_Archive',Mandatory,ValueFromPipelineByPropertyName)]
        [ValidatePattern('^\w{32}$')]
        [Alias('id')]
        [string]$GroupId,
        [Parameter(ParameterSetName='HostId_File',Mandatory,ValueFromPipeline,
            ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName='HostId_Archive',Mandatory,ValueFromPipeline,
            ValueFromPipelineByPropertyName)]
        [ValidatePattern('^\w{32}$')]
        [Alias('HostIds','device_id','host_ids','aid')]
        [string[]]$HostId
    )
    begin {
        # Define output file and temporary folder name
        [string]$DeployName = "FalconDeploy_$(Get-Date -Format FileDateTime)"
        [string]$OutputFile = Join-Path (Get-Location).Path "$DeployName.csv"
        
        function Update-CloudFile ([string]$FileName,[string]$FilePath) {
            # Fields to collect from 'Put' files list
            $Fields = @('id','name','created_timestamp','modified_timestamp','sha256')
            try {
                # Compare 'CloudFile' and 'LocalFile'
                Write-Host "[Invoke-FalconDeploy] Checking cloud for existing file..."
                $CloudFile = @(Get-FalconPutFile -Filter "name:['$FileName']" -Detailed |
                Select-Object $Fields).foreach{
                    [PSCustomObject]@{
                        id                 = $_.id
                        name               = $_.name
                        created_timestamp  = [datetime]$_.created_timestamp
                        modified_timestamp = [datetime]$_.modified_timestamp
                        sha256             = $_.sha256
                    }
                }
                $LocalFile = @(Get-ChildItem $FilePath | Select-Object CreationTime,Name,LastWriteTime).foreach{
                    [PSCustomObject]@{
                        name               = $_.Name
                        created_timestamp  = $_.CreationTime
                        modified_timestamp = $_.LastWriteTime
                        sha256             = ((Get-FileHash $FilePath).Hash).ToLower()
                    }
                }
                if ($LocalFile -and $CloudFile) {
                    if ($LocalFile.sha256 -eq $CloudFile.sha256) {
                        Write-Host "[Invoke-FalconDeploy] Matched hash values between local and cloud files."
                    } else {
                        # Prompt for file choice and remove 'CloudFile' if 'LocalFile' is chosen
                        Write-Host "[CloudFile]"
                        $CloudFile | Select-Object name,created_timestamp,modified_timestamp,sha256 |
                        Format-List | Out-Host
                        Write-Host "[LocalFile]"
                        $LocalFile | Select-Object name,created_timestamp,modified_timestamp,sha256 |
                        Format-List | Out-Host
                        $FileChoice = $host.UI.PromptForChoice(
                            "[Invoke-FalconDeploy] '$FileName' exists in your 'Put' Files. Use existing version?",
                            $null,[System.Management.Automation.Host.ChoiceDescription[]]@("&Yes","&No"),0)
                        if ($FileChoice -eq 0) {
                            Write-Host "[Invoke-FalconDeploy] Proceeding with CloudFile: $($CloudFile.id)..."
                        } else {
                            [System.Object]$RemovePut = $CloudFile.id | Remove-FalconPutFile
                            if ($RemovePut.writes.resources_affected -eq 1) {
                                Write-Host "[Invoke-FalconDeploy] Removed CloudFile: $($CloudFile.id)."
                            }
                        }
                    }
                }
            } catch {
                throw $_
            }
            [System.Object]$AddPut = if ($RemovePut.writes.resources_affected -eq 1 -or !$CloudFile) {
                # Upload 'LocalFile' and output result
                Write-Host "[Invoke-FalconDeploy] Uploading $FileName..."
                $Param = @{
                    Path = $FilePath
                    Name = $FileName
                    Description = $ProcessName
                    Comment = "Invoke-FalconDeploy [$((Show-FalconModule).UserAgent)]"
                }
                Send-FalconPutFile @Param
            }
            if (!$AddPut) {
                throw "Upload failed."
            } elseif ($AddPut -and $AddPut.writes.resources_affected -eq 1) {
                Write-Host "[Invoke-FalconDeploy] Upload complete."
            }
        }
        function Write-RtrResult ([object[]]$Object,[string]$Step,[string]$BatchId) {
            # Create output, append results and output to CSV
            $Output = foreach ($i in $Object) {
                [PSCustomObject]@{
                    aid = $i.aid
                    batch_id = $BatchId
                    session_id = $null
                    cloud_request_id = $null
                    deployment_step = $Step
                    complete = $false
                    offline_queued = $false
                    errors = $null
                    stderr = $null
                    stdout = $null
                }
            }
            $Result = Get-RtrResult $Object $Output
            try { $Result | Export-Csv $OutputFile -Append -NoTypeInformation } catch { $Result }
        }
        # Define output file and verify 'Archive' or 'File' path
        [string]$FilePath = if ($PSBoundParameters.Archive) {
            $Script:Falcon.Api.Path($PSBoundParameters.Archive)
        } else {
            $Script:Falcon.Api.Path($PSBoundParameters.File)
        }
        [string]$FileName = if ($PSBoundParameters.Archive) {
            [System.IO.Path]::GetFileName($FilePath)
        } else {
            $PSBoundParameters.Run
        }
        [string]$ProcessName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        [System.Collections.Generic.List[object]]$HostList = @()
        [System.Collections.Generic.List[string]]$List = @()
    }
    process {
        if ($GroupId) {
            if (($GroupId | Get-FalconHostGroupMember -Total) -gt 10000) {
                # Stop if number of members exceeds API limit
                throw "Group size exceeds maximum number of results. [10,000]"
            } else {
                # Retrieve Host Group member device_id and platform_name
                @($GroupId | Get-FalconHostGroupMember -Detailed -All |
                    Select-Object device_id,platform_name).foreach{ $HostList.Add($_) }
            }
        } elseif ($HostId) {
            # Use provided Host identifiers
            @($HostId).foreach{ $List.Add($_) }
        }
    }
    end {
        if ($List) {
            # Use Host identifiers to also retrieve 'platform_name'
            @($List | Select-Object -Unique | Get-FalconHost | Select-Object device_id,platform_name).foreach{
                $HostList.Add($_)
            }
        }
        if ($HostList) {
            if (Test-Path $FilePath -PathType Leaf) {
                # Check for existing 'CloudFile' and upload 'LocalFile' if chosen
                Update-CloudFile $FileName $FilePath
            }
            try {
                for ($i = 0; $i -lt ($HostList | Measure-Object).Count; $i += 1000) {
                    # Start Real-time Response sessions in groups of 1,000
                    $Param = @{ Id = @($HostList[$i..($i + 999)].device_id) }
                    @('QueueOffline','Timeout').foreach{
                        if ($PSBoundParameters.$_) { $Param[$_] = $PSBoundParameters.$_ }
                    }
                    $Session = Start-FalconSession @Param
                    [string[]]$SessionHosts = if ($Session.batch_id) {
                        # Output result to CSV and return list of successful 'init' hosts
                        Write-RtrResult $Session.hosts 'init' $Session.batch_id
                        ($Session.hosts | Where-Object { $_.complete -eq $true -or
                            $_.offline_queued -eq $true }).aid
                    }
                    if ($SessionHosts) {
                        # Change to a 'temp' directory for each device by platform
                        Write-Host "[Invoke-FalconDeploy] Initiated session with $(($SessionHosts |
                            Measure-Object).Count) host(s)..."
                        foreach ($Pair in (@{
                            Windows = ($HostList | Where-Object { $SessionHosts -contains $_.device_id -and
                                $_.platform_name -eq 'Windows' }).device_id
                            Mac = ($HostList | Where-Object { $SessionHosts -contains $_.device_id -and
                                $_.platform_name -eq 'Mac' }).device_id
                            Linux = ($HostList | Where-Object { $SessionHosts -contains $_.device_id -and
                                $_.platform_name -eq 'Linux' }).device_id
                        }).GetEnumerator().Where({ $_.Value })) {
                            # Set 'Optional' hosts by OS and define target temporary folder
                            [string]$TempDir = switch ($Pair.Key) {
                                'Windows' { "\Windows\Temp\$DeployName" }
                                'Mac' { "/tmp/$DeployName" }
                                'Linux' { "/tmp/$DeployName" }
                            }
                            foreach ($Cmd in @('mkdir','cd','put','runscript','run')) {
                                $Param = @{
                                    BatchId = $Session.batch_id
                                    Command = $Cmd
                                    Argument = switch ($Cmd) {
                                        'mkdir' { $TempDir }
                                        'cd' { $TempDir }
                                        'put' { $FileName }
                                        'runscript' {
                                            $Script = if ($Pair.Key -eq 'Linux') {
                                                if ($PSBoundParameters.Archive) {
                                                    $null # ";chmod +x $(@($TempDir,$PSBoundParameters.Run) -join '/')"
                                                } else {
                                                    "chmod +x $(@($TempDir,$FileName) -join '/')"
                                                }
                                            } elseif ($PSBoundParameters.Archive) {
                                                $null
                                            }
                                            if ($Script) { '-Raw=```{0}```' -f $Script }
                                        }
                                        'run' {
                                            [string]$Join = if ($Pair.Key -eq 'Windows') { '\' } else { '/' }
                                            [string]$CmdFile = @($TempDir,$FileName) -join $Join
                                            if ($PSBoundParameters.Argument) {
                                                $CmdLine = '-CommandLine="{0}"' -f $PSBoundParameters.Argument
                                                $CmdFile,$CmdLine -join ' '
                                            } else {
                                                $CmdFile
                                            }
                                        }
                                    }
                                }
                                $Param['OptionalHostId'] = if ($Cmd -eq 'mkdir') {
                                     # Use initial Host list for 'mkdir'
                                    $Pair.Value
                                } elseif ($Result) {
                                    # Use Host(s) with successful previous 'Cmd'
                                    ($Result | Where-Object { ($_.complete -eq $true -and !$_.stderr) -or
                                        $_.offline_queued -eq $true }).aid
                                }
                                if ($PSBoundParameters.Timeout) { $Param['Timeout'] = $PSBoundParameters.Timeout }
                                $Result = if ($Param.OptionalHostId -and $Param.Argument) {
                                    # Issue command and output result
                                    Write-Host "[Invoke-FalconDeploy] Issuing '$Cmd' to $(($Optional |
                                        Measure-Object).Count) $($Pair.Key) host(s)..."
                                    Invoke-FalconAdminCommand @Param
                                }
                                # Output result to CSV
                                if ($Result) { Write-RtrResult $Result $Cmd $Session.batch_id }
                            }
                        }
                    }
                }
            } catch {
                throw $_
            } finally {
                if (Test-Path $OutputFile) {
                    Get-ChildItem $OutputFile | Select-Object FullName,Length,LastWriteTime
                }
            }
        }
    }
}
function Invoke-FalconRtr {
<#
.SYNOPSIS
Start Real-time Response session,execute a command and output the result
.DESCRIPTION
Requires 'Real Time Response: Read', 'Real Time Response: Write' or 'Real Time Response (Admin): Write'
depending on 'Command' provided.
.PARAMETER Command
Real-time Response command
.PARAMETER Argument
Arguments to include with the command
.PARAMETER Timeout
Length of time to wait for a result, in seconds
.PARAMETER QueueOffline
Add non-responsive Hosts to the offline queue
.PARAMETER Include
Include additional properties
.PARAMETER GroupId
Host group identifier
.PARAMETER HostId
Host identifier
.LINK
https://github.com/crowdstrike/psfalcon/wiki/Real-time-Response
#>
    [CmdletBinding(DefaultParameterSetName='HostId')]
    param(
        [Parameter(ParameterSetName='HostId',Mandatory,Position=1)]
        [Parameter(ParameterSetName='GroupId',Mandatory,Position=1)]
        [ValidateSet('cat','cd','clear','cp','csrutil','cswindiag','encrypt','env','eventlog backup',
            'eventlog export','eventlog list','eventlog view','filehash','get','getsid','history','ifconfig',
            'ipconfig','kill','ls','map','memdump','mkdir','mount','mv','netstat','ps','put','put-and-run',
            'reg delete','reg load','reg query','reg set','reg unload','restart','rm','run','runscript',
            'shutdown','umount','unmap','update history','update install','update list','users','xmemdump','zip',
            IgnoreCase=$false)]
        [string]$Command,
        [Parameter(ParameterSetName='HostId',Position=2)]
        [Parameter(ParameterSetName='GroupId',Position=2)]
        [Alias('Arguments')]
        [string]$Argument,
        [Parameter(ParameterSetName='HostId',Position=3)]
        [Parameter(ParameterSetName='GroupId',Position=3)]
        [ValidateRange(30,600)]
        [int32]$Timeout,
        [Parameter(ParameterSetName='HostId',Position=4)]
        [Parameter(ParameterSetName='GroupId',Position=4)]
        [boolean]$QueueOffline,
        [Parameter(ParameterSetName='HostId',Position=5)]
        [Parameter(ParameterSetName='GroupId',Position=5)]
        [ValidateSet('agent_version','cid','external_ip','first_seen','host_hidden_status','hostname',
            'last_seen','local_ip','mac_address','os_build','os_version','platform_name','product_type',
            'product_type_desc','serial_number','system_manufacturer','system_product_name','tags',
            IgnoreCase=$false)]
        [string[]]$Include,
        [Parameter(ParameterSetName='GroupId',Mandatory)]
        [ValidatePattern('^\w{32}$')]
        [string]$GroupId,
        [Parameter(ParameterSetName='HostId',Mandatory,ValueFromPipeline,ValueFromPipelineByPropertyName)]
        [ValidatePattern('^\w{32}$')]
        [Alias('device_id','host_ids','aid','HostIds')]
        [string[]]$HostId
    )
    begin {
        if ($PSBoundParameters.Timeout -and $PSBoundParameters.Command -eq 'runscript' -and
        $PSBoundParameters.Argument -notmatch '-Timeout=\d{2,3}') {
            # Force 'Timeout' into 'Arguments' when using 'runscript'
            $PSBoundParameters.Argument += " -Timeout=$($PSBoundParameters.Timeout)"
        }
        [System.Collections.Generic.List[string]]$List = @()
    }
    process {
        if ($PSBoundParameters.GroupId) {
            if (($PSBoundParameters.GroupId | Get-FalconHostGroupMember -Total) -gt 10000) {
                # Stop if number of members exceeds API limit
                throw "Group size exceeds maximum number of results. [10,000]"
            } else {
                # Retrieve Host Group member device_id and platform_name
                @($PSBoundParameters.GroupId | Get-FalconHostGroupMember -All).foreach{ $List.Add($_) }
            }
        } elseif ($PSBoundParameters.HostId) {
            # Use provided Host identifiers
            @($PSBoundParameters.HostId).foreach{ $List.Add($_) }
        }
    }
    end {
        if ($List) {
            # Start session using unique identifiers and capture result
            $Output = @($List | Select-Object -Unique).foreach{ [PSCustomObject]@{ aid = $_ }}
            if ($Include) {
                foreach ($i in (Get-FalconHost -Id $Output.aid | Select-Object @($Include + 'device_id'))) {
                    # Append 'Include' fields to output
                    foreach ($Prop in @($i.PSObject.Properties.Where({ $_.Name -ne 'device_id' }))) {
                        $Output | Where-Object { $_.aid -eq $i.device_id } | ForEach-Object {
                            Set-Property $_ $Prop.Name $Prop.Value
                        }
                    }
                }
            }
            if ($GroupId) {
                # Append 'group_id' field to output
                @($Output).foreach{ Set-Property $_ 'group_id' $GroupId }
            }
            $Init = @{ Id = $Output.aid }
            @('QueueOffline','Timeout').foreach{ if ($PSBoundParameters.$_) { $Init[$_] = $PSBoundParameters.$_ }}
            $InitReq = Start-FalconSession @Init
            if ($InitReq.batch_id -or $InitReq.session_id) {
                $Output = if ($InitReq.hosts) {
                    @(Get-RtrResult $InitReq.hosts $Output).foreach{
                        # Clear 'stdout' from batch initialization
                        if ($_.stdout) { $_.stdout = $null }
                        $_
                    }
                } else {
                    Get-RtrResult $InitReq $Output
                }
                # Issue command and capture result
                $Cmd = @{ Command = $Command }
                @('Argument','Timeout').foreach{ if ($PSBoundParameters.$_) { $Cmd[$_] = $PSBoundParameters.$_ }}
                if ($QueueOffline -ne $true) { $Cmd['Confirm'] = $true }
                $CmdReq = $InitReq | & "$(Get-RtrCommand $Command)" @Cmd
                $Output = Get-RtrResult $CmdReq $Output
                [string[]]$Select = @($Output).foreach{
                    # Clear 'stdout' for batch 'get' requests
                    if ($_.stdout -and $_.batch_get_cmd_req_id) { $_.stdout = $null }
                    if ($_.stdout -and $Cmd.Command -eq 'runscript') {
                        # Attempt to convert 'stdout' from Json for 'runscript'
                        $StdOut = try { $_.stdout | ConvertFrom-Json } catch { $null }
                        if ($StdOut) { $_.stdout = $StdOut }
                    }
                    # Output list of fields for each object
                    $_.PSObject.Properties.Name
                } | Sort-Object -Unique
                # Force output of all unique fields
                $Output | Select-Object $Select
            }
        }
    }
}