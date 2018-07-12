CREATE PROCEDURE [dbo].[prc_GL_CheckImportXmlTypes]
	@xml	xml,
	@types	xml,
	@errors	xml = NULL output,
	@NoCheckColumnsCount bit = 0,
	@Debug bit = 0
-------------------------------------------------------------------------------------
--	Процедура проверяет соответствуют ли типы значений в @xml типам из @types
--	Используется в процедурах для методов импорта из Excel в Liasoft Workspace
--	Список ячеек в @xml должен быть полным, без пропусков
-------------------------------------------------------------------------------------
--	Автор:	Мамонов А.В.
--	Модуль:	Общее
--	Дата:	10/07/2013
-------------------------------------------------------------------------------------
--	@xml	- Стандартный XML переданный в процедуру импорта методом из Workspace
--	@types	- XML с типами колонок и возможностью NULL значений
--	@errors	- XML с ошибками
/*
		Типы ошибок:
			-1 - не найден тип в системе
			 0 - нет ошибки
			 2 - Требуется значение
			 3 - Ошибочный тип данных 
			 4 - Проверка переполнения в типе
*/
--	@NoCheckColumnsCount - 1 - если не передаётся @types не по всем колонкам
-------------------------------------------------------------------------------------
--	Запуск:
/*
DECLARE 
	@xml xml, @types xml, @Count int, @errors xml
SET @xml = '<Workbook Path="C:\Users\Public\Documents\бц1.xlsx"><Sheet i="1" n="Лист1">
<Row i="2"><Cell i="1" n="A2">8</Cell><Cell i="2" n="B2">25</Cell><Cell i="3" n="C2"/><Cell i="4" n="D2">2013-07-12T00:00:00</Cell><Cell i="5" n="E2">1</Cell></Row>
<Row i="3"><Cell i="1" n="A3">23</Cell><Cell i="2" n="B3">30</Cell><Cell i="3" n="C3"/><Cell i="4" n="D3">2013-07-12T00:00:00</Cell><Cell i="5" n="E3">12</Cell></Row>
</Sheet></Workbook>'

SET @types = '<Types>
	<Column i="1" type="varchar(16)" nullable="0"/>
	<Column i="2" type="money" nullable="1"/>
	<Column i="3" type="decimal(4,2)" nullable="1"/>
	<Column i="4" type="smalldatetime" nullable="0"/>
	<Column i="5" type="int" nullable="0"/>
	</Types>'

Exec @Count = [dbo].[prc_GL_CheckImportXmlTypes] @xml,@types, @errors output,NULL--, 1
select @Count,@errors

select ISNUMERIC('2123.9')
select CAST('2,123.9' as decimal(24,3))
select CASE WHEN '-12' LIKE '%[^0-9-]%' THEN 1 ELSE 0 END
-------------------------------------------------------

	sp_helptext prc_GL_CheckImportXmlTypes

declare @errors xml

Exec [dbo].[prc_GL_CheckImportXmlTypes] @xml = 
'<Workbook Path="C:\Users\Public\Documents\Фиксированные цены.xls"><Sheet i="1" n="Лист1">
<Row i="2"><Cell i="1" n="A2">10570</Cell><Cell i="2" n="B2">2015-01-30T00:00:00</Cell><Cell i="3" n="C2">25</Cell><Cell i="4" n="D2">14</Cell></Row>
<Row i="3"><Cell i="1" n="A3">4589</Cell><Cell i="2" n="B3">2015-01-30T00:00:00</Cell><Cell i="3" n="C3">15</Cell><Cell i="4" n="D3">5</Cell></Row>
</Sheet></Workbook>'
,@types= 
'<Types>
	<Column i="1" type="varchar(3)" nullable="0"/>
	<Column i="2" type="smalldatetime" nullable="0"/>
	<Column i="3" type="money" nullable="0"/>
	<Column i="4" type="int" nullable="0"/>
</Types>'
, @errors=@errors output, @NoCheckColumnsCount=1, @Debug = 1
select @errors


*/
-------------------------------------------------------------------------------------
--	Изменения:
--	17/12/2013: Проверка типа теперь CONVERT вместо CAST, из-за проблем с датой
--	11/12/2014: Поправил вывод номера строки из Excel, @types может содержать не все колонки,
--				а только нужные, добавил в вывод ошибок значение ячейки CellValue
--				убрал TRY CATCH, т.к. в блоке CATCH возникает uncommittable transaction
--				Убрал цикл и добавил селект в ошибки проверки типов по колонкам
--	09/02/2015: Проверка числового типа по [^0-9-., ] и ISNUMERIC(REPLACE(REPLACE(@check,' ',''),',',''))
--				Допустимы символы: 0-9 - . , ISNUMERIC не ест разделители групп разрядов
--				Конкретизировал имена числовых типов и даты
--	29/03/2016 Приказчикова М.Н. Исправлена ошибка при сравнении столбца с допустиммым значением NULL. C153117
--	11/04/2016 Мамонов А.В.: Исправил обрезку 4-х символов при отсутствии записей в @types,
--				Добавил проверку, что передаётся хотя бы один тип в @types
--	22/12/2016 Оптимизировал динамический запрос разворачивания xml в таблицу #XML
--	02/02/2018 Переделал проверку типа на TRY_CONVERT, добавил тип uniqueidentifier, 
--				добавил проверку переполнения по размерности типа
-------------------------------------------------------------------------------------
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE
		@xmlxsd xml(DOCUMENT ExcelImportSchemaCollection),
		@ErrMsg varchar(MAX)

	IF EXISTS(SELECT 1 FROM sys.xml_schema_collections WHERE name = N'ExcelImportSchemaCollection')
		BEGIN TRY
			SET @xmlxsd = CAST(@xml AS xml(DOCUMENT ExcelImportSchemaCollection))
		END TRY
		BEGIN CATCH
			SET @ErrMsg = ISNULL(ERROR_MESSAGE(), 'Ошибка валидации xml')
			RAISERROR ('Ошибка валидации xml: %s ', 16, 1, @ErrMsg)
			RETURN 50001
		END CATCH 
	ELSE SET @xmlxsd = @xml

/*	
	SET XACT_ABORT OFF
	
	DECLARE @XACT_ABORT VARCHAR(3) 
	set @XACT_ABORT =  'OFF';
	IF ( (16384 & @@OPTIONS) = 16384 ) SET @XACT_ABORT = 'ON';
	SELECT @XACT_ABORT AS XACT_ABORT;
*/

	DECLARE @typesT TABLE(Num int, TypeFName varchar(60), Nullable bit)
--	DECLARE @errorsT TABLE(Num int IDENTITY(1,1),ErrorCode int, RowNum int, CellNum int, CellName varchar(10), CellValue varchar(max), ErrorRus varchar(255), ErrorMessage varchar(255), TypeName varchar(16))

	INSERT INTO @typesT(Num,TypeFName,Nullable)
	SELECT 
		T.item.value('@i[1]','int'),
		LOWER(T.item.value('@type[1]','varchar(30)')),
		T.item.value('@nullable[1]','bit')
	FROM 
		@types.nodes('//Types/Column') T(item)	

	IF(@Debug = 1)
		SELECT
			*
		FROM
			@typesT

	DECLARE
		@CountRows	int,			-- кол-во строк
--		@CountCells	int,			-- кол-во ячеек в строке
		@CountCols	int,			-- ожидаемое кол-во ячеек в строке из @types
--		@CurrR		int,			-- текущая позиция строки
--		@CurrC		int,			-- текущая позиция ячейки
--		@CellName	varchar(10),	-- имя ячейки
--		@V			NVARCHAR(MAX),	-- значение в текущей ячейке
		@SQL		NVARCHAR(MAX),	-- запрос на проверку приведения к типу
		@TypeFName	varchar(60),	-- тип приведения полный
		@TypeName	varchar(60),	-- тип приведения
		@Nullable	bit,			-- возможность NULL значения
		@ErrorCount	int,			-- кол-во ошибок ИТОГО
--		@RowIndex	int,			-- номер строки в i=
		@Scale		varchar(20),	-- размерность типа
--		@max_length	int,			-- размер данных типа
--		@is_date	bit,			-- признак даты
		@MaxColumns int,			-- кол-во колонок
--		@is_string  bit,			-- строковый тип
--		@is_numeric	bit,			-- числовой тип
		@ColIndex	int				-- номер колонки

	SELECT 
		@CountRows = @xmlxsd.query('count(//Workbook/Sheet/Row)').value('.', 'INT')
--		@CurrR = 1,
--		@CurrC = 1

--	SET @CountCols = @types.query('count(//Types/Column)').value('.', 'INT')

	SELECT @MaxColumns = MAX(Num) FROM @typesT

	SET @CountCols = @types.query('count(//Types/Column)').value('.', 'INT')
	SET @ColIndex = -1
	
	CREATE TABLE #xmlxsd
	(
		RN int NOT NULL,
		CN int NOT NULL,
		CNN varchar(10) NOT NULL,
		CV varchar(300) NULL
	)
	CREATE CLUSTERED INDEX [IX_prc_GL_CheckImportXmlTypes_xmlxsd_RC] ON #xmlxsd(RN,CN)

	INSERT INTO #xmlxsd
	SELECT	
		th.ih.value('@i[1]','int'), 
		t.i.value('@i','int'), 
		t.i.value('@n','varchar(10)'), 
		t.i.value('.','varchar(300)')
	FROM
		@xmlxsd.nodes('//Workbook/Sheet/Row') th(ih)
		CROSS APPLY th.ih.nodes('Cell') as t(i)

	IF(@Debug = 1)
		SELECT
			*
		FROM
			#xmlxsd
			
	CREATE TABLE #errorsT 
	(
		Num int IDENTITY(1,1),
		ErrorCode int, 
		RowNum int, 
		CellNum int, 
		CellName varchar(10), 
		CellValue varchar(max), 
		ErrorRus varchar(255), 
		ErrorMessage varchar(255), 
		TypeFName varchar(60),
		TypeName varchar(60),
		Scale varchar(20)
	)

	CREATE TABLE #XML
	(
		ID int
	)
	CREATE NONCLUSTERED INDEX [IX_prc_GL_CheckImportXmlTypes_errorsT_ErrorCode] ON #errorsT([ErrorCode]);

	DECLARE
		@ColumnNum int,
		@MaxColumnNum int,
		@SQLAddColumn varchar(512),
		@SQLAddCellName varchar(512),
		@SQLParams nvarchar(max),
		@Error varchar(max),
		@InTran bit,
		@rn varchar(2)

	SET @InTran = CASE WHEN @@TRANCOUNT > 0 THEN 1 ELSE 0 END

	SET @rn = CHAR(13)+CHAR(10)

	SET @ColumnNum = -1
	SET @SQL = 'SELECT ' + @rn + ' RN,' + @rn
	
	--'	T.item.value(''@i[1]'',''int''), ' + @rn
	SELECT @MaxColumnNum = COUNT(*) FROM @typesT

	IF(@MaxColumnNum = 0)
	BEGIN
		RAISERROR('Ошибка: не переданы типы колонок.',16,1)
		IF @InTran = 1 ROLLBACK TRANSACTION
		RETURN 50001
	END

	WHILE 1=1
	BEGIN
		SELECT TOP 1
			@ColumnNum = Num,
			@TypeFName = 'varchar(100)',--TypeFName,
			@SQLAddColumn = 'ALTER TABLE #XML ADD Column_'+CAST(Num AS varchar(12)) + ' ' + 'varchar(300)' + CASE WHEN ISNULL(Nullable,1)= 1 THEN ' NULL' ELSE '' END + '',
			@SQLAddCellName = 'ALTER TABLE #XML ADD CellName_'+CAST(Num AS varchar(12)) + ' ' + 'varchar(10)' 
		FROM
			@typesT
		WHERE
			Num > @ColumnNum
		ORDER BY 
			Num

		IF @@ROWCOUNT < 1 BREAK

		--T.item.value('Cell[sql:variable("@ActionPosition")][1]','varchar(10)')
--		SET @SQL = @SQL + '	T.item.value(''Cell[' + CAST(@ColumnNum AS varchar(12)) + '][1]'',''varchar(100)''), ' + @rn
--		SET @SQL = @SQL + ' T.item.value(''(Cell[' + CAST(@ColumnNum AS varchar(12)) + '][1]/@n)[1]'',''varchar(10)''), ' + @rn

		SET @SQL = @SQL + ' MAX(CASE CN WHEN ' + CAST(@ColumnNum AS varchar(12)) + ' THEN CV ELSE NULL END), ' + @rn
		SET @SQL = @SQL + ' MAX(CASE CN WHEN ' + CAST(@ColumnNum AS varchar(12)) + ' THEN CNN ELSE NULL END), ' + @rn

		BEGIN TRY
			IF(@Debug = 1) print @SQLAddColumn
			EXEC(@SQLAddColumn)
			IF(@Debug = 1) print @SQLAddCellName
			EXEC(@SQLAddCellName)
		END TRY
		BEGIN CATCH
			SET @Error = ERROR_MESSAGE()
			RAISERROR('Ошибка построения таблицы проверки типов: %s',16,1,@Error)
			IF @InTran = 1 ROLLBACK TRANSACTION
			RETURN 50001
		END CATCH
	END

	SET @SQL = SUBSTRING(@SQL,1,LEN(@SQL)-4)
	SET @SQL = @SQL + @rn + 'FROM ' +  @rn + '#xmlxsd GROUP BY RN'
	--'	@xmlxsd.nodes(''//Workbook/Sheet/Row'') T(item)'

	SET @SQL = 'INSERT INTO #XML ' + @rn + @SQL

	BEGIN TRY
		IF(@Debug = 1) print @SQL

		SET @SQLParams = N'
			@xmlxsd xml
		'

		EXECUTE sp_executesql @SQL, @SQLParams, @xmlxsd
	END TRY
	BEGIN CATCH
		SET @Error = ERROR_MESSAGE()
		RAISERROR('Ошибка построения таблицы проверки типов: %s',16,1,@Error)
		IF @InTran = 1 ROLLBACK TRANSACTION
		RETURN 50001
	END CATCH

	IF(@Debug = 1 ) SELECT * FROM #XML

	-- цикл по каждому столбцу
	SET @ColumnNum = -1
	WHILE 1=1
	BEGIN
		SELECT TOP 1
			@ColumnNum = Num,
			@TypeFName = TypeFName,
			@Nullable = Nullable
		FROM
			@typesT
		WHERE
			Num > @ColumnNum
		ORDER BY
			Num

		IF @@ROWCOUNT = 0 BREAK
			
		SET @Scale = 0	-- размерность типа
		IF(PATINDEX('%(%',@TypeFName) > 0) 
		BEGIN
			SET @Scale = SUBSTRING(@TypeFName, PATINDEX('%(%',@TypeFName) + 1, LEN(@TypeFName) - PATINDEX('%(%',@TypeFName) - 1 ) -- от скобки до скобки
			IF(PATINDEX('%,%',@Scale) > 0)	-- если есть указание точности - берем именно размерность
				SET @Scale = SUBSTRING(@Scale,1,PATINDEX('%,%',@Scale)-1)

			SET @TypeName = SUBSTRING(LOWER(@TypeFName),1,PATINDEX('%(%',@TypeFName)-1)

		END

		SET @SQL = '
		INSERT INTO #errorsT(ErrorCode,RowNum,CellNum,CellName,CellValue,ErrorMessage,TypeFName,TypeName,[Scale])
		SELECT 
			CASE
				WHEN t.system_type_id IS NULL THEN -1
				WHEN @Nullable = 1 AND ISNULL(Column_'+CAST(@ColumnNum as varchar(10))+','''') = '''' THEN 0		-- пустой и допустимо
				WHEN @Nullable = 0 AND LEN(ISNULL(Column_'+CAST(@ColumnNum as varchar(10))+','''')) = 0 THEN 2
--				WHEN @Scale > 0 AND LEN(ISNULL(Column_'+CAST(@ColumnNum as varchar(10))+','''')) > @Scale THEN 4	-- переполнение
				WHEN LEN(ISNULL(Column_'+CAST(@ColumnNum as varchar(10))+','''')) > LEN(TRY_CONVERT('+@TypeFName+', Column_'+CAST(@ColumnNum as varchar(10))+')) THEN 4
				WHEN TRY_CONVERT('+@TypeFName+', Column_'+CAST(@ColumnNum as varchar(10))+') IS NULL THEN 3
				ELSE 0
			END,
			ID,
			@ColumnNum,
			CellName_'+CAST(@ColumnNum as varchar(10))+',
			Column_'+CAST(@ColumnNum as varchar(10)) +',
			NULL,
			@TypeFName,
			@TypeName,
			@Scale
		FROM
			#XML x
			LEFT JOIN sys.types t WITH(NOLOCK) ON
				t.name = LOWER(@TypeName) 
		ORDER BY 
			ID
		'

		IF(@Debug = 1) print @SQL

		EXECUTE sp_executesql @SQL, N'@TypeFName varchar(60),@TypeName varchar(60), @ColumnNum int, @Nullable bit, @Scale varchar(20)',@TypeFName, @TypeName,@ColumnNum,@Nullable,@Scale
		
	END

	SELECT TOP 1
		@TypeName = TypeName,
		@ColIndex = RowNum
	FROM	
		#errorsT
	WHERE
		ErrorCode = (-1)
	
	IF @@ROWCOUNT > 0
	BEGIN
		RAISERROR('[Строка %i] Не найден тип (%s) в T-SQL.',16,1,@ColIndex,@TypeName)
		IF @InTran = 1 ROLLBACK TRANSACTION
		RETURN 50001
	END

	DELETE FROM #errorsT WHERE ErrorCode = 0 -- не ошибки 

	UPDATE
		tm
	SET
		ErrorRus = CASE ErrorCode 
						WHEN 2 THEN 'Пустое значение не допустимо. Ожидается тип - ' 
						WHEN 3 THEN 'Ошибочный тип данных, ожидается тип - ' 
						WHEN 4 THEN 'Превышение размерности ('+[Scale]+' символов), ожидается тип - ' 
					END +
					CASE
						WHEN TypeName LIKE '%date%' THEN 'дата'
						WHEN TypeName IN ('tinyint','smallint','int','bigint') THEN 'целый тип'
						WHEN TypeName IN ('real','money','float','decimal','numeric','smallmoney') THEN 'вещественное число'
						WHEN TypeName IN ('varchar','char','nvarchar','text','ntext','sysname') THEN 'строка\текст (или символ)'
						WHEN TypeName = 'uniqueidentifier' THEN 'GUID (00000000-0000-0000-0000-000000000000)'
						ELSE TypeName
					END +
					' ['+TypeFName+']'
	FROM
		#errorsT tm
	WHERE
		ErrorCode IN (2,3,4)

	IF(@Debug = 1) SELECT * FROM #errorsT

	SELECT @ErrorCount = COUNT(*) FROM #errorsT

	-- выводим ошибки в переменную xml
	IF(@ErrorCount > 0)
		SET @errors = 
		(
			SELECT * FROM 
			(
				SELECT			
					1 as Tag,
					NULL as Parent,
					@ErrorCount as [Errors!1!ErrorCount],
					NULL as [Error!2!ErrorCode],
					NULL as [Error!2!RowNum],
					NULL as [Error!2!CellNum],
					NULL as [Error!2!CellName],
					NULL as [Error!2!CellValue],
					NULL as [Error!2!ErrorRus],
					NULL as [Error!2!ErrorMessage]
				UNION ALL
				SELECT
					2 as Tag,
					1 as Parent,
					NULL,
					ErrorCode,
					RowNum,
					CellNum,
					CellName,
					CellValue,
					ErrorRus,
					ErrorMessage
				FROM
					#errorsT
			
			)as Errors 
			FOR XML EXPLICIT
		)
	RETURN @ErrorCount

	/* Compare */
END
GO

