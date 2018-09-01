/*
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[prc_GL_ReorganizeTableIndex]') AND type in (N'P', N'PC'))
DROP PROCEDURE [dbo].[prc_GL_ReorganizeTableIndex]
GO
*/
CREATE PROCEDURE [dbo].[prc_GL_ReorganizeTableIndex]
	@TableListXml xml,	-- XML со списком таблиц, для которых дефрагментировать индексы
	@Debug bit = 0		-- отладка, только показывает
-------------------------------------------------------------------------------------
--	Процедура дефрагментирует индексы для таблиц, логгирует в таблицу ReorganizeTableIndexLog
--  Procedure defragment table indexes listed in incoming xml
-------------------------------------------------------------------------------------
--	Автор:	Мамонов А.В.
--	Модуль:	Общий
--	Дата:	28/12/2016
-------------------------------------------------------------------------------------
--  Запуск:
/*
	DECLARE
		@TableListXml xml

	SET @TableListXml = '
		<TableList>
			<Table Name="PLFormulaRefArh"/>
			<Table Name="ArhPriceList"/>
			<Table Name="le_PLBasePrice"/>
			<Table Name="PLDiscountLayerValues"/>
			<Table Name="PLDiscountSettings"/>
			<Table Name="PLDiscountLayerSettings"/>
			<Table Name="Products"/>
			<Table Name="c_Products"/>
			<Table Name="c_UnsecuredProducts"/>
		</TableList>
	'
	Exec [dbo].prc_GL_ReorganizeTableIndex @TableListXml = @TableListXml, @Debug = 1
*/
-------------------------------------------------------------------------------------
--	Изменения:
-------------------------------------------------------------------------------------
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE
		@PersentMIN int,
		@PersentRebuild int,
		@AllIndexes	bit,
		@MaxRunTimeSec bigint,
		@PageCountMIN bigint

	-------------------------------------------------------------------------------------
	--	Настроки процедуры, пока тут
	-------------------------------------------------------------------------------------
	SELECT 
		@PersentMIN = 15,		-- минимальный % для выполнения дефрагментации [15], minimal % for starting defragmentation process
		@PersentRebuild = 40,	-- пороговый % для REBUILD [40], bound % for rebuil instead of reindex
		@AllIndexes = 0,		-- работа по каждому индексу (0) или сразу по всем (1) [0], defrag each index (0), or al for table (1)
		@MaxRunTimeSec = 60*35,	-- Кол-во секунд максимум на выполнение дефрагментации [35*60] -- 35 минут, maximum time procedure working in sec
		@PageCountMIN = 50		-- Минимальный размер индекса в страницах для дефрагментации [50], Minmum index size for defrag start
	-------------------------------------------------------------------------------------
	DECLARE
		@StartTime datetime,
		@CurrTime datetime,
		@InnerTime datetime

	SELECT 
		@StartTime = GETDATE(),
		@Debug = ISNULL(@Debug,0)
	-------------------------------------------------------------------------------------
	--	XML в табличку
	-------------------------------------------------------------------------------------
	IF (NOT OBJECT_ID('tempdb..#TableList') IS NULL) 
		DROP TABLE #TableList

	CREATE TABLE #TableList
	(
		RowTableID int NOT NULL IDENTITY(1,1),
		TableName varchar(100) NOT NULL
	)
	INSERT INTO #TableList(TableName)
	SELECT 
		T.item.value('@Name[1]','varchar(100)') as TableName
	FROM
		@TableListXml.nodes('//TableList/Table') T(item)

	IF(@Debug = 1)
		SELECT 
			*
		FROM
			#TableList

	DECLARE
		@TableName varchar(100),
		@RowTableID int,
		@RowIndexID int,
		@IndexName nvarchar(100),
		@OP_TYPE nvarchar(20),
		@PersentCur decimal(20,12),
		@DSQL nvarchar(MAX),
		@SchemaName nvarchar(50),
		@tr varchar(2)

	SET @tr = CHAR(13)+ CHAR(10)

	SET @RowTableID = -1

	-------------------------------------------------------------------------------------
	--	Для каждой таблицы
	-------------------------------------------------------------------------------------
	WHILE(1=1)
	BEGIN
		IF(DATEDIFF(ss,@StartTime,GETDATE()) > @MaxRunTimeSec) RETURN 1

		SELECT TOP 1
			@RowTableID = RowTableID,
			@TableName = TableName
		FROM
			#TableList
		WHERE
			RowTableID > @RowTableID
		ORDER BY
			RowTableID			

		IF(@@ROWCOUNT = 0) BREAK

		IF (OBJECT_ID('tempdb..#TABLE_INDEX_FRAGMENTATION') IS NOT NULL) 
			DROP TABLE #TABLE_INDEX_FRAGMENTATION

		SELECT 
			ROW_NUMBER() OVER(ORDER BY indexstats.avg_fragmentation_in_percent DESC) as RowIndexID,
			dbschemas.[name] as 'SchemaName', 
			dbtables.[name] as 'TableName', 
			dbindexes.[name] as 'IndexName',
			indexstats.avg_fragmentation_in_percent,
			indexstats.page_count,
			indexstats.[object_id],
			indexstats.index_id,
			indexstats.fragment_count, 
			dbindexes.fill_factor, 
			indexstats.partition_number
		INTO 
			#TABLE_INDEX_FRAGMENTATION
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
			(@TableName IS NULL OR dbtables.[name] = @TableName) AND
			dbindexes.[name] IS NOT NULL AND				-- Except HEAPs
			indexstats.page_count > @PageCountMIN			-- внушительные индексы
		ORDER BY 
			indexstats.index_id desc,						--Сначала не кластерные индексы
			indexstats.avg_fragmentation_in_percent desc	--Далее по степени фрагментации

		IF(@@ROWCOUNT = 0) BREAK

		IF(@Debug = 1)
			SELECT 
			*
			FROM
				#TABLE_INDEX_FRAGMENTATION

		IF(@AllIndexes = 1) 
		BEGIN

			SELECT TOP 1
				@SchemaName = SchemaName,
				@PersentCur = MAX(avg_fragmentation_in_percent)
			FROM
				#TABLE_INDEX_FRAGMENTATION	
			WHERE
				avg_fragmentation_in_percent >= @PersentMIN 
			GROUP BY
				SchemaName

			IF(@@ROWCOUNT = 0) BREAK

			IF(@PersentCur > @PersentRebuild) SET @OP_TYPE = 'REBUILD'
			ELSE SET @OP_TYPE = 'REORGANIZE'

			SET @DSQL = '-- MAX fragmentation = '+CAST(@PersentCur as varchar(20)) + '%' + @tr
			SET @DSQL = @DSQL + 'ALTER INDEX ALL ON [' + @SchemaName + '].[' + @TableName + '] ' + @OP_TYPE + ';' + @tr + @tr
			PRINT @DSQL

			IF(@Debug = 0) 
			BEGIN
				SET @InnerTime = GETDATE()
				EXEC(@DSQL)

				INSERT INTO ReorganizeTableIndexLog
				(			
					[object_id],
	--				index_id,
					start_time,
					end_time,
					table_name,
	--				index_name,
					avg_frag_percent_before,
					fragment_count_before,
					pages_count_before,
					fill_factor,
					partition_num,
					avg_frag_percent_after,
					fragment_count_after,
					pages_count_after,
					[action],
					AllIndexes
				)
				SELECT
					bef.[object_id],
					@InnerTime as start_time,
					GETDATE() as end_time,
					@TableName as TableName,
					MAX(bef.avg_fragmentation_in_percent) as avg_fragmentation_in_percent_before,
					MAX(bef.fragment_count) as fragment_count_before,
					MAX(bef.page_count) as pages_count_before,
					AVG(bef.fill_factor) as fill_factor,
					MAX(bef.partition_number) as partition_num,
					MAX(indexstats.avg_fragmentation_in_percent) as avg_fragmentation_in_percent_after,
					MAX(indexstats.fragment_count) as fragment_count_after,
					MAX(indexstats.page_count) as pages_count_after,
					@OP_TYPE as [action],
					1 as AllIndexes
				FROM
					#TABLE_INDEX_FRAGMENTATION bef
					OUTER APPLY sys.dm_db_index_physical_stats (DB_ID(), OBJECT_ID(@TableName), NULL, NULL, NULL) AS indexstats
					INNER JOIN sys.tables dbtables WITH(NOLOCK) ON 
						dbtables.[object_id] = indexstats.[object_id]
					INNER JOIN sys.schemas dbschemas WITH(NOLOCK) ON 
						dbtables.[schema_id] = dbschemas.[schema_id]
					INNER JOIN sys.indexes AS dbindexes WITH(NOLOCK) ON 
						dbindexes.[object_id] = indexstats.[object_id]
						AND indexstats.index_id = dbindexes.index_id
				GROUP BY
					bef.[object_id]

				SET @DSQL = ''
			END

		END
		ELSE
		BEGIN

			SET @RowIndexID = -1

			WHILE(1=1)
			BEGIN

				IF(DATEDIFF(ss,@StartTime,GETDATE()) > @MaxRunTimeSec) 
				BEGIN
					select DATEDIFF(ss,@StartTime,GETDATE())
					RETURN 1
				END

				SELECT TOP 1
					@RowIndexID = RowIndexID,
					@SchemaName = SchemaName,
					@IndexName = IndexName,
					@PersentCur = avg_fragmentation_in_percent
				FROM
					#TABLE_INDEX_FRAGMENTATION
				WHERE
					RowIndexID > @RowIndexID AND
					avg_fragmentation_in_percent >= @PersentMIN 

				ORDER BY
					RowIndexID

				IF @@ROWCOUNT = 0 BREAK

				IF(@PersentCur > @PersentRebuild) SET @OP_TYPE = 'REBUILD'
				ELSE SET @OP_TYPE = 'REORGANIZE'

				SET @DSQL = '-- fragmentation = '+CAST(@PersentCur as varchar(20)) + '%' + @tr
				SET @DSQL = @DSQL + 'ALTER INDEX [' + @IndexName + '] ON [' + @SchemaName + '].[' + @TableName + '] ' + @OP_TYPE + ';' + @tr + @tr
				PRINT @DSQL

				IF(@Debug = 0)
				BEGIN
					SET @InnerTime = GETDATE()
					EXEC(@DSQL)
		
					INSERT INTO ReorganizeTableIndexLog
					(			
						[object_id],
						index_id,
						start_time,
						end_time,
						table_name,
						index_name,
						avg_frag_percent_before,
						fragment_count_before,
						pages_count_before,
						fill_factor,
						partition_num,
						avg_frag_percent_after,
						fragment_count_after,
						pages_count_after,
						[action],
						AllIndexes
					)
					SELECT
						bef.[object_id],
						bef.[index_id],
						@InnerTime as start_time,
						GETDATE() as end_time,
						@TableName as TableName,
						@IndexName as IndexName,
						bef.avg_fragmentation_in_percent as avg_fragmentation_in_percent_before,
						bef.fragment_count as fragment_count_before,
						bef.page_count as pages_count_before,
						bef.fill_factor as fill_factor,
						bef.partition_number as partition_num,
						indexstats.avg_fragmentation_in_percent as avg_fragmentation_in_percent_after,
						indexstats.fragment_count as fragment_count_after,
						indexstats.page_count as pages_count_after,
						@OP_TYPE as [action],
						0 as AllIndexes
					FROM
						#TABLE_INDEX_FRAGMENTATION bef
						INNER JOIN sys.dm_db_index_physical_stats (DB_ID(), OBJECT_ID(@TableName), NULL, NULL, NULL) AS indexstats ON
							indexstats.index_id = bef.index_id
						INNER JOIN sys.tables dbtables WITH(NOLOCK) ON 
							dbtables.[object_id] = indexstats.[object_id]
						INNER JOIN sys.schemas dbschemas WITH(NOLOCK) ON 
							dbtables.[schema_id] = dbschemas.[schema_id]
						INNER JOIN sys.indexes AS dbindexes WITH(NOLOCK) ON 
							dbindexes.[object_id] = indexstats.[object_id]
							AND indexstats.index_id = dbindexes.index_id
					WHERE
						RowIndexID = @RowIndexID

					SET @DSQL = ''
				END
			END

		END

	END

	RETURN 0
END
GO

GRANT EXECUTE ON [dbo].[prc_GL_ReorganizeTableIndex] TO Public
GO


