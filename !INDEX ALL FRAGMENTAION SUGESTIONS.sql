-------------------------------------------------------------------------------------
--	Скрипт выводит фрагментированные индексы по таблицы (или все) в порядке убывания
--  Script returns ordered fragmented indexes for table with % and scripts for reindex or rebuild each of them
-------------------------------------------------------------------------------------
--	Автор:	Мамонов А.В.
--	Дата:	09.06.2015
----------------------------------------------------------------------------------
--	Изменения:
-------------------------------------------------------------------------------------
/*
ALTER INDEX ALL ON [dbo].[PLFormulaRefArh] REBUILD;
GO
ALTER INDEX ALL ON [dbo].[ArhPriceList] REBUILD;
GO
ALTER INDEX [IX_ArhPriceList_ProductID_PolType_Status] ON [dbo].[ArhPriceList] REORGANIZE;
GO
*/
DECLARE
	@TableName nvarchar(450),
	@Persent decimal(4,2),
	@AllIndexes bit,
	@DSQL nvarchar(MAX)

-- пороговый процент для отображения
SET @Persent = 0

-- можно повсем или по одной таблице ( @TableName = NULL -- все)
SET @TableName = N'MatProducts'

-- все индексы таблицы или каждый отдельно
SET @AllIndexes = 0

-------------------------------------------------------------------------------------
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(@TableName) AND type in (N'U'))
BEGIN
	RAISERROR ('Не найдена %s таблица в текущей БД',16,1,@TableName)
	GOTO END_SCRIPT
END
/*
SELECT DISTINCT OBJECT_NAME(sis.OBJECT_ID) TableName, si.name AS IndexName, sc.Name AS ColumnName,
sic.Index_ID, sis.user_seeks, sis.user_scans, sis.user_lookups, sis.user_updates
FROM sys.dm_db_index_usage_stats sis
INNER JOIN sys.indexes si ON sis.OBJECT_ID = si.OBJECT_ID AND sis.Index_ID = si.Index_ID
INNER JOIN sys.index_columns sic ON sis.OBJECT_ID = sic.OBJECT_ID AND sic.Index_ID = si.Index_ID
INNER JOIN sys.columns sc ON sis.OBJECT_ID = sc.OBJECT_ID AND sic.Column_ID = sc.Column_ID
WHERE sis.Database_ID = DB_ID(DB_NAME()) AND sis.OBJECT_ID = OBJECT_ID(@TableName);
*/

/*
-- Кол-во записей в таблице
SELECT DB_NAME() as DBNAME
SET @DSQL = '
	SELECT COUNT(*) as [Кол-во записей в таблице] FROM '+@TableName+' WITH(NOLOCK)'

EXEC(@DSQL)

*/

IF (NOT OBJECT_ID('tempdb..#INDEX_FRAGMENTATION') IS NULL) 
DROP TABLE #INDEX_FRAGMENTATION

SELECT 
	ROW_NUMBER() OVER(ORDER BY indexstats.avg_fragmentation_in_percent DESC) as ROWID,
	dbschemas.[name] as 'SchemaName', 
	dbtables.[name] as 'TableName', 
	dbindexes.[name] as 'IndexName',
	indexstats.avg_fragmentation_in_percent,
	indexstats.page_count
INTO 
	#INDEX_FRAGMENTATION
FROM 
	sys.dm_db_index_physical_stats (DB_ID(), OBJECT_ID(@TableName), NULL, NULL, NULL) AS indexstats
	INNER JOIN sys.tables dbtables WITH(NOLOCK) ON 
		dbtables.[object_id] = indexstats.[object_id]
	INNER JOIN sys.schemas dbschemas WITH(NOLOCK) ON 
		dbtables.[schema_id] = dbschemas.[schema_id]
	INNER JOIN sys.indexes AS dbindexes WITH(NOLOCK) ON 
		dbindexes.[object_id] = indexstats.[object_id]
		AND indexstats.index_id = dbindexes.index_id
WHERE 
	indexstats.database_id = DB_ID() AND
	indexstats.avg_fragmentation_in_percent >= @Persent AND
	(@TableName IS NULL OR dbtables.[name] = @TableName) AND
	dbindexes.[name] IS NOT NULL -- Except HEAPs
ORDER BY 
	indexstats.avg_fragmentation_in_percent desc

SELECT 
	*
FROM
	#INDEX_FRAGMENTATION
ORDER BY 
	avg_fragmentation_in_percent desc

DECLARE
	@ROWID int,
	@IndexName nvarchar(450),
	@SchemaName nvarchar(50),
	@tr varchar(2),
	@PersentCur decimal(20,12),
	@OP_TYPE varchar(100)

SET @tr = CHAR(13)+ CHAR(10)
SET @ROWID = 0
SET @TableName = ''

WHILE 1=1
BEGIN
	SELECT TOP 1
		@ROWID = ROWID,
		@SchemaName = SchemaName,
		@IndexName = IndexName,
		@TableName = TableName,
		@PersentCur = avg_fragmentation_in_percent
	FROM
		#INDEX_FRAGMENTATION
	WHERE
		ROWID > @ROWID AND
		(@AllIndexes = 0 OR @TableName <> TableName)
	ORDER BY 
		ROWID

	IF @@ROWCOUNT < 1 BREAK

	IF (@PersentCur <= 5) CONTINUE

	IF(@PersentCur >= 30) SET @OP_TYPE = 'REBUILD'
	ELSE SET @OP_TYPE = 'REORGANIZE'

	IF(@AllIndexes = 0) 
	BEGIN
		PRINT '-- ' + @IndexName + ': ' + CAST(@PersentCur as varchar(50)) + ' %'
		PRINT 'ALTER INDEX [' + @IndexName + '] ON [' + @SchemaName + '].[' + @TableName + '] ' + @OP_TYPE + ';' + @tr
	END
	ELSE
	BEGIN
		PRINT '-- ' + @TableName
		PRINT 'ALTER INDEX ALL ON [' + @SchemaName + '].[' + @TableName + '] ' + @OP_TYPE + ';' + @tr

	END

	PRINT 'GO'+ @tr + @tr

END
EXEC('sp_help '+@TableName)

END_SCRIPT:
	
GO