use HYPER

IF (NOT OBJECT_ID('tempdb..#t') IS NULL) 
DROP TABLE #t

-- таблица, которую собираем на филиалах
CREATE TABLE #t(
	[op_id] [int]  NOT NULL,
	[object_id] [int] NOT NULL,
	[index_id] [int] NULL,
	[start_time] [datetime] NOT NULL,
	[end_time] [datetime] NOT NULL,
	[table_name] [varchar](50) NOT NULL,
	[index_name] [varchar](50) NULL,
	[avg_frag_percent_before] [float] NOT NULL,
	[fragment_count_before] [bigint] NOT NULL,
	[pages_count_before] [bigint] NOT NULL,
	[fill_factor] [tinyint] NOT NULL,
	[partition_num] [int] NOT NULL,
	[avg_frag_percent_after] [float] NOT NULL,
	[fragment_count_after] [bigint] NOT NULL,
	[pages_count_after] [bigint] NOT NULL,
	[action] [nvarchar](50) NOT NULL,
	[AllIndexes] [bit] NOT NULL,
		
	InstallationID int,
	LegalEntityID int,
	[Server] varchar(20), 
	[Base] varchar(20),
	[Филиал] varchar(300)
)

-- таблица с филиалами (все, действующие)
DECLARE @fla TABLE(InstallationID int,LegalEntityID int, [Description] varchar(250), ServerName varchar(20),DatabaseName varchar(20),[DBState] int,[State] int)

INSERT INTO @fla
SELECT 

--top 1
	SI.InstallationID,
	SI.LegalEntityID,
	SI.LegalEntityName as ShortNameRus,
	SI.ServerName,
	SI.DatabaseName,
	CAST(0 as int) as [DBState],
	SI.IsClosed as [State] 
FROM 
	dbo.fnc_CMDB_GetMirrorDB(default) SI	   
WHERE 
		(
			SI.HeadInstallationID = 1 OR 
			SI.InstallationID = 1
			--OR SI.HeadInstallationID IS NULL
		) 
		AND IsClosed = 0
ORDER BY 
		SI.LegalEntityID		

SELECT TOP 100 * FROM	@fla

---------------------------------------------------------

DECLARE
	@l int ,
	@i int,
	@server varchar(20),
	@base varchar(20),
	@sql nvarchar(max),
	@FName varchar(256)
	
SET @l = -1

WHILE (1=1)
BEGIN
	
	SELECT TOP 1
		@server =  ServerName,
		@base = DatabaseName,
		@l = LegalEntityID,
		@i = InstallationID,
		@FName = [Description]
	FROM
		@fla
	WHERE
		LegalEntityID > @l AND
		[DBState]=0
		
	IF(@@ROWCOUNT < 1) BREAK
	
	--select @server,@base
	
	SET @sql = '
	
	SELECT
		*
		,'+CAST(@i as varchar(10))+',
		'+CAST(@l as varchar(10))+',
		'''+@server+''',
		'''+@base+''',
		'''+@FName+'''
	FROM
		ReorganizeTableIndexLog
'


	--print @sql
	SET @sql = 'EXEC '+@server+'.'+@base+'.sys.sp_executesql N'''+REPLACE(@sql,'''','''''')+''''
	print @sql
--	EXEC(@sql)
	INSERT INTO #t
	EXEC sys.sp_executesql @sql--, @SQLParams2

	IF(@@ERROR <> 0) BREAK

END
---------------------------------------------------------
	

SELECT DISTINCT
	a.*,
	v.LegalEntityCode

FROM 
	#t a
	INNER JOIN [vcmdb_ISystemInstallations] v ON
		a.InstallationID = v.InstallationID
		AND a.LegalEntityID = v.LegalEntityID
		AND v.InstallationTypeID=1
		AND v.SystemID in (1,2)

ORDER BY
	a.LegalEntityID

/*
	where
		[Status] in (5,6)
order by
	1

	
SELECT sum([Кол-во 1])
	
FROM 
	#t a
GROUP BY
	[Status]
order by
	1

	*/
