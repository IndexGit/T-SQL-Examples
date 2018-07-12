/*
SELECT TOP 100  * FROM sys.default_constraints
SELECT TOP 100 * FROM sys.columns
SELECT TOP 1 * FROM sys.objects WHERE name = 'RawDoc'
SELECT TOP 100 * FROM sys.types

SELECT * FROM #tbl ORDER BY UID
*/

DECLARE
	@Object_Name varchar(50),
	@Func_name varchar(50),
	@Print	bit
	
SET @Object_Name = 'StoreZone'
SET @Func_name = '%user%'
SET @Print = 1			-- печатать скрипт

SET NOCOUNT ON 
IF OBJECT_ID(N'tempdb.dbo.#tbl') IS NOT NULL
	DROP TABLE #tbl 

CREATE TABLE #tbl(
	[UID] int identity(1,1),
	defc_id int,
	defc_name nvarchar(128),
	t_name nvarchar(128),
	c_name nvarchar(128),
	c_type nvarchar(128),
	c_length int,
	defc_type int DEFAULT(0), -- 0 - constraint, 1- bind
	[status] int DEFAULT(0),
	err varchar(max))

INSERT INTO #tbl(defc_id, defc_name, t_name, c_name, c_type, c_length,defc_type)
SELECT
	def.[object_id],
	def.name as df_name,
	tbl.name AS t_name,
	col.name AS c_name,
	st.name AS c_type,
	col.max_length AS c_length,
	CASE WHEN def.parent_object_id = tbl.object_id THEN 0 ELSE 1 END 	
FROM
	sys.objects tbl WITH (NOLOCK) 
	INNER JOIN sys.columns col WITH (NOLOCK) ON
		col.[object_id] = tbl.[object_id] 
	INNER JOIN sys.types st WITH (NOLOCK) ON
		st.system_type_id = col.system_type_id AND
		st.system_type_id = st.user_type_id AND -- условие для полечение системного типа
		st.name IN ('varchar', 'nvarchar', 'char') -- только строковые типы
	INNER JOIN syscomments com WITH (NOLOCK) ON
		com.id = col.default_object_id
		AND UPPER(com.[text]) like UPPER(@Func_name)
		AND UPPER(com.[text]) not like UPPER('%Utl_GetUserName%')
	INNER JOIN sys.objects def WITH(NOLOCK)
		ON def.[object_id] = col.default_object_id		
WHERE
	tbl.name LIKE @Object_Name AND
	tbl.[type] = 'U' AND
	col.default_object_id <> 0

INSERT INTO #tbl(defc_id, defc_name, t_name, c_name, c_type, c_length)
SELECT
	defc.[object_id] AS defc_id,
	defc.name AS defc_name,
	tbl.name AS t_name,
	col.name AS c_name,
	st.name AS c_type,
	col.max_length AS c_length
	--defc.*, col.*
FROM
	sys.default_constraints defc WITH (NOLOCK)
	INNER JOIN sys.objects tbl WITH (NOLOCK) ON
		tbl.[object_id] = defc.parent_object_id AND
		tbl.[type] = 'U'
	INNER JOIN sys.columns col WITH (NOLOCK) ON
		col.[object_id] = tbl.[object_id] AND
		col.column_id = defc.parent_column_id
	INNER JOIN sys.types st WITH (NOLOCK) ON
		st.system_type_id = col.system_type_id AND
		st.system_type_id = st.user_type_id AND -- условие для полечение системного типа
		st.name IN ('varchar', 'nvarchar', 'char') -- только строковые типы
	INNER JOIN syscomments com WITH (NOLOCK) ON
		defc.[object_id] = com.id
		AND UPPER(com.[text]) like UPPER(@Func_name)
		AND UPPER(com.[text]) not like UPPER('%Utl_GetUserName%')		
	left join #tbl
		ON #tbl.defc_id = defc.[object_id]
WHERE
	tbl.name LIKE @Object_Name AND
	UPPER(defc.[definition]) LIKE UPPER(@Func_name)
	AND  #tbl.defc_id is NULL
ORDER BY
	defc.[object_id]
	

SELECT * FROM #tbl	ORDER BY defc_type DESC,[UID] ASC

IF(@Print = 0) GOTO M_END

DECLARE
	@ret_tatus int,
	@sql nvarchar(max),
	@def_difinition varchar(255),
	@UID int,
	@defc_id int,
	@defc_name nvarchar(128),
	@t_name nvarchar(128),
	@c_name nvarchar(128),
	@c_type nvarchar(128),
	@c_length int,
	@defc_type	int

SET @UID = -1

WHILE 0=0
BEGIN
	SELECT TOP 1
		@UID = [UID],
		@defc_id = defc_id,
		@defc_name = defc_name,
		@t_name = t_name,
		@c_name = c_name,
		@c_type = c_type,
		@c_length = c_length,
		@defc_type = defc_type,
		@def_difinition = 'DEFAULT ' + 
			CASE 
				WHEN @c_length >= 128 THEN '(dbo.Utl_GetUserNameFromContextInfoForDefault())' -- если размерность позволяет CONVERT не нужен
				ELSE '(CONVERT(' + @c_type + '(' + CONVERT(varchar(10), @c_length) + '), dbo.Utl_GetUserNameFromContextInfoForDefault()))'
			END
	FROM
		#tbl
	WHERE
		ISNULL([status], 0) = 0 AND
		[UID] > @UID --AND [UID] = 154
	ORDER BY
		[UID] ASC, defc_type DESC

	IF @@ROWCOUNT = 0 BREAK
	
	BEGIN TRY

		BEGIN TRAN
		-- удаляем DEFAULT
		IF(@defc_type = 0) -- бинды не трогаем
		BEGIN
		SET @sql = '---- ' + @t_name + CHAR(13) + CHAR(10) +
			'IF  EXISTS (SELECT 1 FROM dbo.sysobjects WHERE id = OBJECT_ID(N''[dbo].[' + @defc_name + ']'') AND type = ''D'')' +
			CHAR(13) + CHAR(10) +
			'BEGIN' + CHAR(13) + CHAR(10) +
			'	ALTER TABLE [dbo].[' + @t_name + '] DROP CONSTRAINT [' + @defc_name + ']'+ CHAR(13) + CHAR(10)  +
			'END' + CHAR(13) + CHAR(10)  +
			'GO'  + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) 
			PRINT @sql
		END

		-- drop new
		SET @sql = 'IF EXISTS (SELECT 1 FROM dbo.sysobjects WHERE id = OBJECT_ID(N''[dbo].[DEF_' + @t_name + '_' + @c_name + ']'') AND type = ''D'')' +
			CHAR(13) + CHAR(10) +		
		-- создаем DEFAULT
			'	ALTER TABLE [dbo].[' + @t_name + '] ' +	'DROP CONSTRAINT [DEF_' + @t_name + '_' + @c_name + '] ' + CHAR(13) + CHAR(10)  +
		'GO'  + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
		PRINT @sql			
		
		IF(@defc_type = 1) -- если это бинд
		BEGIN
			SET @sql = 'IF  EXISTS (SELECT 1 FROM dbo.sysobjects SO	'+
			'INNER JOIN dbo.syscolumns SC ON SC.id = SO.id ' +
			'INNER JOIN dbo.sysobjects SD ON SD.id = SC.cdefault ' +
			'WHERE SO.Name = ''' + @t_name + ''' AND SC.Name = ''' + @c_name + ''' AND SD.name = '''+@defc_name+''')' + CHAR(13) + CHAR(10)+
			'	EXECUTE sp_unbindefault N''dbo.'+@t_name+'.'+@c_name+'''' + CHAR(13) + CHAR(10)+
			'GO'+ CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) 
			PRINT @sql
		END

		--EXEC @ret_tatus = sp_executesql @sql
		--IF @@ERROR <> 0 OR @ret_tatus <> 0 RAISERROR 50001 'ERROR DROP CONSTRAINT'
				
		-- создаем DEFAULT
		SET @sql = 'IF NOT EXISTS (SELECT * FROM dbo.sysobjects WHERE id = OBJECT_ID(N''[dbo].[DEF_' + @t_name + '_' + @c_name + ']'') AND type = ''D'')' +
			CHAR(13) + CHAR(10) +
		'BEGIN' + CHAR(13) + CHAR(10) +
			'	ALTER TABLE [dbo].[' + @t_name + '] ' +
			'ADD CONSTRAINT [DEF_' + @t_name + '_' + @c_name + '] ' + @def_difinition +
			' FOR [' + @c_name + ']' + CHAR(13) + CHAR(10)  +
		
		'END' + CHAR(13) + CHAR(10)  +
		'GO'  + CHAR(13) + CHAR(10) 
		--EXEC @ret_tatus = sp_executesql @sql
		--IF @@ERROR <> 0 OR @ret_tatus <> 0 RAISERROR 50002 'ERROR ADD CONSTRAINT'
		
		PRINT @sql
		
		PRINT '------------------------------------'+ CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) 
		
		UPDATE
			#tbl
		SET
			[status] = 1,
			err = NULL
		WHERE
			[UID] = @UID

		WHILE @@TRANCOUNT > 0 COMMIT TRAN
	END TRY
	BEGIN CATCH

		WHILE @@TRANCOUNT > 0 ROLLBACK TRAN
		UPDATE
			#tbl
		SET
			[status] = 0,
			err = ERROR_MESSAGE()
		WHERE
			[UID] = @UID
			
		SELECT @UID AS UID, ERROR_MESSAGE() AS err
	END CATCH
END

M_END: