function Edit-FalconFirewallPolicy {
<#
.SYNOPSIS
Modify Falcon Firewall Management policies
.DESCRIPTION
Requires 'Firewall Management: Write'.
.PARAMETER Array
An array of policies to modify in a single request
.PARAMETER Id
Policy identifier
.PARAMETER Name
Policy name
.PARAMETER Description
Policy description
.LINK
https://github.com/crowdstrike/psfalcon/wiki/Edit-FalconFirewallPolicy
#>
    [CmdletBinding(DefaultParameterSetName='/policy/entities/firewall/v1:patch',SupportsShouldProcess)]
    param(
        [Parameter(ParameterSetName='array',Mandatory,ValueFromPipeline)]
        [ValidateScript({
            foreach ($Object in $_) {
                $Param = @{
                    Object = $Object
                    Command = 'Edit-FalconFirewallPolicy'
                    Endpoint = '/policy/entities/firewall/v1:patch'
                    Required = @('id')
                    Pattern = @('id')
                }
                Confirm-Parameter @Param
            }
        })]
        [Alias('resources')]
        [object[]]$Array,
        [Parameter(ParameterSetName='/policy/entities/firewall/v1:patch',Mandatory,Position=1)]
        [ValidatePattern('^[a-fA-F0-9]{32}$')]
        [string]$Id,
        [Parameter(ParameterSetName='/policy/entities/firewall/v1:patch',Position=2)]
        [string]$Name,
        [Parameter(ParameterSetName='/policy/entities/firewall/v1:patch',Position=3)]
        [string]$Description
    )
    begin {
        $Param = @{
            Command = $MyInvocation.MyCommand.Name
            Endpoint = '/policy/entities/firewall/v1:patch'
            Format = @{
                Body = @{
                    resources = @('name','id','description')
                    root = @('resources')
                }
            }
        }
        [System.Collections.Generic.List[object]]$List = @()
    }
    process {
        if ($Array) {
            foreach ($i in $Array) {
                # Select allowed fields, when populated
                [string[]]$Select = @('id','name','description').foreach{ if ($i.$_) { $_ }}
                $List.Add(($i | Select-Object $Select))
            }
        } else {
            Invoke-Falcon @Param -Inputs $PSBoundParameters
        }
    }
    end {
        if ($List) {
            for ($i = 0; $i -lt $List.Count; $i += 100) {
                $PSBoundParameters['Array'] = @($List[$i..($i + 99)])
                Invoke-Falcon @Param -Inputs $PSBoundParameters
            }
        }
    }
}
function Get-FalconFirewallPolicy {
<#
.SYNOPSIS
Search for Falcon Firewall Management policies
.DESCRIPTION
Requires 'Firewall Management: Read'.
.PARAMETER Id
Policy identifier
.PARAMETER Filter
Falcon Query Language expression to limit results
.PARAMETER Sort
Property and direction to sort results
.PARAMETER Limit
Maximum number of results per request
.PARAMETER Include
Include additional properties
.PARAMETER Offset
Position to begin retrieving results
.PARAMETER Detailed
Retrieve detailed information
.PARAMETER All
Repeat requests until all available results are retrieved
.PARAMETER Total
Display total result count instead of results
.LINK
https://github.com/crowdstrike/psfalcon/wiki/Get-FalconFirewallPolicy
#>
    [CmdletBinding(DefaultParameterSetName='/policy/queries/firewall/v1:get',SupportsShouldProcess)]
    param(
        [Parameter(ParameterSetName='/policy/entities/firewall/v1:get',Mandatory,ValueFromPipelineByPropertyName,
            ValueFromPipeline)]
        [ValidatePattern('^[a-fA-F0-9]{32}$')]
        [Alias('Ids')]
        [string[]]$Id,
        [Parameter(ParameterSetName='/policy/combined/firewall/v1:get',Position=1)]
        [Parameter(ParameterSetName='/policy/queries/firewall/v1:get',Position=1)]
        [ValidateScript({ Test-FqlStatement $_ })]
        [string]$Filter,
        [Parameter(ParameterSetName='/policy/combined/firewall/v1:get',Position=2)]
        [Parameter(ParameterSetName='/policy/queries/firewall/v1:get',Position=2)]
        [ValidateSet('created_by.asc','created_by.desc','created_timestamp.asc','created_timestamp.desc',
            'enabled.asc','enabled.desc','modified_by.asc','modified_by.desc','modified_timestamp.asc',
            'modified_timestamp.desc','name.asc','name.desc','platform_name.asc','platform_name.desc',
            'precedence.asc','precedence.desc',IgnoreCase=$false)]
        [string]$Sort,
        [Parameter(ParameterSetName='/policy/combined/firewall/v1:get',Position=3)]
        [Parameter(ParameterSetName='/policy/queries/firewall/v1:get',Position=3)]
        [ValidateRange(1,5000)]
        [int32]$Limit,
        [Parameter(ParameterSetName='/policy/entities/firewall/v1:get',Position=2)]
        [Parameter(ParameterSetName='/policy/combined/firewall/v1:get',Position=4)]
        [Parameter(ParameterSetName='/policy/queries/firewall/v1:get',Position=4)]
        [ValidateSet('members','settings',IgnoreCase=$false)]
        [string[]]$Include,
        [Parameter(ParameterSetName='/policy/combined/firewall/v1:get')]
        [Parameter(ParameterSetName='/policy/queries/firewall/v1:get')]
        [int32]$Offset,
        [Parameter(ParameterSetName='/policy/combined/firewall/v1:get',Mandatory)]
        [switch]$Detailed,
        [Parameter(ParameterSetName='/policy/combined/firewall/v1:get')]
        [Parameter(ParameterSetName='/policy/queries/firewall/v1:get')]
        [switch]$All,
        [Parameter(ParameterSetName='/policy/queries/firewall/v1:get')]
        [switch]$Total
    )
    begin {
        $Param = @{
            Command = $MyInvocation.MyCommand.Name
            Endpoint = $PSCmdlet.ParameterSetName
            Format = @{ Query = @('sort','ids','offset','filter','limit') }
        }
        [System.Collections.Generic.List[string]]$List = @()
    }
    process { if ($Id) { @($Id).foreach{ $List.Add($_) }}}
    end {
        if ($List) { $PSBoundParameters['Id'] = @($List | Select-Object -Unique) }
        if ($Include) {
            Invoke-Falcon @Param -Inputs $PSBoundParameters | ForEach-Object {
                $Request = Add-Include $_ $PSBoundParameters @{
                    members = 'Get-FalconFirewallPolicyMember'
                    settings = 'Get-FalconFirewallSetting'
                }
                $Request
            }
        } else {
            Invoke-Falcon @Param -Inputs $PSBoundParameters
        }
    }
}
function Get-FalconFirewallPolicyMember {
<#
.SYNOPSIS
Search for Falcon Firewall Management policy members
.DESCRIPTION
Requires 'Firewall Management: Read'.
.PARAMETER Id
Policy identifier
.PARAMETER Filter
Falcon Query Language expression to limit results
.PARAMETER Sort
Property and direction to sort results
.PARAMETER Limit
Maximum number of results per request
.PARAMETER Offset
Position to begin retrieving results
.PARAMETER Detailed
Retrieve detailed information
.PARAMETER All
Repeat requests until all available results are retrieved
.PARAMETER Total
Display total result count instead of results
.LINK
https://github.com/crowdstrike/psfalcon/wiki/Get-FalconFirewallPolicyMember
#>
    [CmdletBinding(DefaultParameterSetName='/policy/queries/firewall-members/v1:get',SupportsShouldProcess)]
    param(
        [Parameter(ParameterSetName='/policy/queries/firewall-members/v1:get',ValueFromPipelineByPropertyName,
            ValueFromPipeline,Position=1)]
        [Parameter(ParameterSetName='/policy/combined/firewall-members/v1:get',ValueFromPipelineByPropertyName,
            ValueFromPipeline,Position=1)]
        [ValidatePattern('^[a-fA-F0-9]{32}$')]
        [string]$Id,
        [Parameter(ParameterSetName='/policy/queries/firewall-members/v1:get',Position=2)]
        [Parameter(ParameterSetName='/policy/combined/firewall-members/v1:get',Position=2)]
        [ValidateScript({ Test-FqlStatement $_ })]
        [string]$Filter,
        [Parameter(ParameterSetName='/policy/queries/firewall-members/v1:get',Position=3)]
        [Parameter(ParameterSetName='/policy/combined/firewall-members/v1:get',Position=3)]
        [string]$Sort,
        [Parameter(ParameterSetName='/policy/queries/firewall-members/v1:get',Position=4)]
        [Parameter(ParameterSetName='/policy/combined/firewall-members/v1:get',Position=4)]
        [ValidateRange(1,5000)]
        [int32]$Limit,
        [Parameter(ParameterSetName='/policy/queries/firewall-members/v1:get')]
        [Parameter(ParameterSetName='/policy/combined/firewall-members/v1:get')]
        [int32]$Offset,
        [Parameter(ParameterSetName='/policy/combined/firewall-members/v1:get',Mandatory)]
        [switch]$Detailed,
        [Parameter(ParameterSetName='/policy/combined/firewall-members/v1:get')]
        [Parameter(ParameterSetName='/policy/queries/firewall-members/v1:get')]
        [switch]$All,
        [Parameter(ParameterSetName='/policy/queries/firewall-members/v1:get')]
        [switch]$Total
    )
    begin {
        $Param = @{
            Command = $MyInvocation.MyCommand.Name
            Endpoint = $PSCmdlet.ParameterSetName
            Format = @{ Query = @('sort','offset','filter','id','limit') }
        }
    }
    process { Invoke-Falcon @Param -Inputs $PSBoundParameters }
}
function Invoke-FalconFirewallPolicyAction {
<#
.SYNOPSIS
Perform actions on Falcon Firewall Management policies
.DESCRIPTION
Requires 'Firewall Management: Write'.
.PARAMETER Name
Action to perform
.PARAMETER GroupId
Host group identifier
.PARAMETER Id
Policy identifier
.LINK
https://github.com/crowdstrike/psfalcon/wiki/Invoke-FalconFirewallPolicyAction
#>
    [CmdletBinding(DefaultParameterSetName='/policy/entities/firewall-actions/v1:post',SupportsShouldProcess)]
    param(
        [Parameter(ParameterSetName='/policy/entities/firewall-actions/v1:post',Mandatory,Position=1)]
        [ValidateSet('add-host-group','disable','enable','remove-host-group',IgnoreCase=$false)]
        [Alias('action_name')]
        [string]$Name,
        [Parameter(ParameterSetName='/policy/entities/firewall-actions/v1:post',Position=2)]
        [ValidatePattern('^[a-fA-F0-9]{32}$')]
        [string]$GroupId,
        [Parameter(ParameterSetName='/policy/entities/firewall-actions/v1:post',Mandatory,
            ValueFromPipelineByPropertyName,ValueFromPipeline,Position=3)]
        [ValidatePattern('^[a-fA-F0-9]{32}$')]
        [string]$Id
    )
    begin {
        $Param = @{
            Command = $MyInvocation.MyCommand.Name
            Endpoint = $PSCmdlet.ParameterSetName
            Format = @{
                Query = @('action_name')
                Body = @{ root = @('ids','action_parameters') }
            }
        }
    }
    process {
        $PSBoundParameters['Ids'] = @($PSBoundParameters.Id)
        [void]$PSBoundParameters.Remove('Id')
        if ($PSBoundParameters.GroupId) {
            $PSBoundParameters['action_parameters'] = @(
                @{
                    name = 'group_id'
                    value = $PSBoundParameters.GroupId
                }
            )
            [void]$PSBoundParameters.Remove('GroupId')
        }
        Invoke-Falcon @Param -Inputs $PSBoundParameters
    }
}
function New-FalconFirewallPolicy {
<#
.SYNOPSIS
Create Falcon Firewall Management policies
.DESCRIPTION
Requires 'Firewall Management: Write'.
.PARAMETER Array
An array of policies to create in a single request
.PARAMETER Name
Policy name
.PARAMETER PlatformName
Operating system platform
.PARAMETER Description
Policy description
.LINK
https://github.com/crowdstrike/psfalcon/wiki/New-FalconFirewallPolicy
#>
    [CmdletBinding(DefaultParameterSetName='/policy/entities/firewall/v1:post',SupportsShouldProcess)]
    param(
        [Parameter(ParameterSetName='array',Mandatory,ValueFromPipeline)]
        [ValidateScript({
            foreach ($Object in $_) {
                $Param = @{
                    Object = $Object
                    Command = 'New-FalconFirewallPolicy'
                    Endpoint = '/policy/entities/firewall/v1:post'
                    Required = @('name','platform_name')
                    Content = @('platform_name')
                    Format = @{ platform_name = 'PlatformName' }
                }
                Confirm-Parameter @Param
            }
        })]
        [Alias('resources')]
        [object[]]$Array,
        [Parameter(ParameterSetName='/policy/entities/firewall/v1:post',Mandatory,Position=1)]
        [string]$Name,
        [Parameter(ParameterSetName='/policy/entities/firewall/v1:post',Mandatory,Position=2)]
        [ValidateSet('Windows','Mac','Linux',IgnoreCase=$false)]
        [Alias('platform_name')]
        [string]$PlatformName,
        [Parameter(ParameterSetName='/policy/entities/firewall/v1:post',Position=3)]
        [string]$Description
    )
    begin {
        $Param = @{
            Command = $MyInvocation.MyCommand.Name
            Endpoint = '/policy/entities/firewall/v1:post'
            Format = @{
                Body = @{
                    resources = @('description','platform_name','name')
                    root = @('resources')
                }
            }
        }
        [System.Collections.Generic.List[object]]$List = @()
    }
    process {
        if ($Array) {
            foreach ($i in $Array) {
                # Select allowed fields, when populated
                [string[]]$Select = @('name','description','platform_name').foreach{ if ($i.$_) { $_ }}
                $List.Add(($i | Select-Object $Select))
            }
        } else {
            Invoke-Falcon @Param -Inputs $PSBoundParameters
        }
    }
    end {
        if ($List) {
            for ($i = 0; $i -lt $List.Count; $i += 100) {
                $PSBoundParameters['Array'] = @($List[$i..($i + 99)])
                Invoke-Falcon @Param -Inputs $PSBoundParameters
            }
        }
    }
}
function Remove-FalconFirewallPolicy {
<#
.SYNOPSIS
Remove Falcon Firewall Management policies
.DESCRIPTION
Requires 'Firewall Management: Write'.
.PARAMETER Id
Policy identifier
.LINK
https://github.com/crowdstrike/psfalcon/wiki/Remove-FalconFirewallPolicy
#>
    [CmdletBinding(DefaultParameterSetName='/policy/entities/firewall/v1:delete',SupportsShouldProcess)]
    param(
        [Parameter(ParameterSetName='/policy/entities/firewall/v1:delete',Mandatory,
            ValueFromPipelineByPropertyName,ValueFromPipeline,Position=1)]
        [ValidatePattern('^[a-fA-F0-9]{32}$')]
        [Alias('Ids')]
        [string[]]$Id
    )
    begin {
        $Param = @{
            Command = $MyInvocation.MyCommand.Name
            Endpoint = $PSCmdlet.ParameterSetName
            Format = @{ Query = @('ids') }
        }
        [System.Collections.Generic.List[string]]$List = @()
    }
    process { if ($Id) { @($Id).foreach{ $List.Add($_) }}}
    end {
        if ($List) {
            $PSBoundParameters['Id'] = @($List | Select-Object -Unique)
            Invoke-Falcon @Param -Inputs $PSBoundParameters
        }
    }
}
function Set-FalconFirewallPrecedence {
<#
.SYNOPSIS
Set Falcon Firewall Management policy precedence
.DESCRIPTION
All policy identifiers must be supplied in order (with the exception of the 'platform_default' policy) to define
policy precedence.

Requires 'Firewall Management: Write'.
.PARAMETER PlatformName
Operating system platform
.PARAMETER Id
Policy identifiers in desired precedence order
.LINK
https://github.com/crowdstrike/psfalcon/wiki/Set-FalconFirewallPrecedence
#>
    [CmdletBinding(DefaultParameterSetName='/policy/entities/firewall-precedence/v1:post',SupportsShouldProcess)]
    param(
        [Parameter(ParameterSetName='/policy/entities/firewall-precedence/v1:post',Mandatory,Position=1)]
        [ValidateSet('Windows','Mac','Linux',IgnoreCase=$false)]
        [Alias('platform_name')]
        [string]$PlatformName,
        [Parameter(ParameterSetName='/policy/entities/firewall-precedence/v1:post',Mandatory,Position=2)]
        [ValidatePattern('^[a-fA-F0-9]{32}$')]
        [Alias('Ids')]
        [string[]]$Id
    )
    begin {
        $Param = @{
            Command = $MyInvocation.MyCommand.Name
            Endpoint = $PSCmdlet.ParameterSetName
            Format = @{ Body = @{ root = @('platform_name','ids') }}
        }
    }
    process { Invoke-Falcon @Param -Inputs $PSBoundParameters }
}