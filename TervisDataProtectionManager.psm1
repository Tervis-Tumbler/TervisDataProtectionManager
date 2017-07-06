function Invoke-GetDPMServices {
$Services = @"
DPM
DPM Replication Agent
SQLAgent`$MSSQLSERVER
MSSQL`$MSSQLSERVER
Virtual Disk Service
Volume Shadow Copy
"@ -split "`r`n" | Get-Service -ComputerName inf-scdpm201601
}

function Get-DataSourceInfo {
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$DataSourceID
    )
    process {
        Invoke-SQL -dataSource inf-scdpm201601 -database DPMDB_INF_SCDPM201601 -sqlCommand @"
exec dbo.prc_PRM_GetDataSourceInfo '$DataSourceID'
"@ -ConvertFromDataRow
    }
}


function Get-IMDataSource {
    Invoke-SQL -dataSource inf-scdpm201601 -database DPMDB_INF_SCDPM201601 -sqlCommand @"
SELECT *  FROM [DPMDB_INF_SCDPM201601].[dbo].[tbl_IM_DataSource]
"@ -ConvertFromDataRow
#tbl_PRM_DatasourceConfigInfo
}

function Get-ARMDataSource {
    Invoke-SQL -dataSource inf-scdpm201601 -database DPMDB_INF_SCDPM201601 -sqlCommand @"
SELECT *  FROM [DPMDB_INF_SCDPM201601].[dbo].[tbl_ARM_Datasource]
"@ -ConvertFromDataRow
#tbl_PRM_DatasourceConfigInfo
}



function Invoke-Test {
    #Get-DataSourceInfo -DataSourceID '4C907872-A6EB-499C-9E2E-F66894050EA4'

    $IMDataSources = Get-IMDataSource
    $ARMDataSources = Get-ARMDataSource
    $Results = $DataSources | Get-DataSourceInfo
}