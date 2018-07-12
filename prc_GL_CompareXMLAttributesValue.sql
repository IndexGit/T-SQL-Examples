/*
IF EXISTS (SELECT 1 FROM dbo.sysobjects WHERE id = OBJECT_ID(N'[dbo].[prc_GL_CompareXMLAttributesValue]') AND type = 'P')
	DROP PROCEDURE [dbo].[prc_GL_CompareXMLAttributesValue]
GO
*/
CREATE PROCEDURE [dbo].[prc_GL_CompareXMLAttributesValue]
  @xml xml,
  @xml2 xml,
	@a_list nvarchar(max),
	@result int OUT,
	@changed_alist nvarchar(max) OUT,
	@is_simple_comapre int = 1
AS
/*

	Описание: 
		Сравнение xml
	
	Параметры:
		@xml и @xml2 сравниваемые переменные

	Запуск:
		DECLARE
			@xml xml,
			@xml2 xml,
			@result int

		SET @xml = '
			<ss>
				<Adress AdressID="66" ClientID="1" />
			</ss>'

		SET @xml2 = '
			<ss>
				<Adress AdressID="66" ClientID="12" />
			</ss>'

		EXEC prc_GL_CompareXMLAttributesValue
			@xml = xml,
			@xml2 = @xml2,
			@a_list = 'ClientID',
			@result = @result OUT

	История изменений:
		2013/04/09 - Передних Р.Н. Создание
		2015/02/04 - Приказчикова М.Н. Форматирование.С106471
		2015/09/10, Передних Р.Н., Добавлен параметр @is_simple_comapre позволяющий выводить перчень полей, даже если одно из них
			отсутствует в одном из сравниваемых образцов. По умолчанию такая возможность отменена
		2015/09/10 Полянский К.Э. Проверка по атрибутам, цикл по каждому xml.
*/

BEGIN
	DECLARE
		@attCnt int,
		@attCnt2 int,
		@attCnt1 int,
		@cnt int,
		@cnt2 int,
		@attName varchar(max),
		@attValue varchar(max),
		@elCnt int,
		@elCnt2 int,
		@x1 xml,
		@x2 xml

	SET @result = 0
	IF @changed_alist IS NULL SET @changed_alist = ''

	-- If one of the arguments is NULL then we assume that they are not equal. 
	IF @xml IS NULL OR @xml2 IS NULL 
	BEGIN
		SET @result = 1
		RETURN
	END

	-- Сравниваем название элементов
	IF (SELECT @xml.value('(local-name((/*)[1]))','VARCHAR(MAX)')) <> 
		(SELECT @xml2.value('(local-name((/*)[1]))','VARCHAR(MAX)'))
	BEGIN
		SET @result = 1
		RETURN
	END

	-- Сравниваем количество атрибутов	
	SET @attCnt = @xml.query('count(/*/@*)').value('.','int')
	SET @attCnt2 = @xml2.query('count(/*/@*)').value('.','int')

	IF @attCnt <> @attCnt2 AND @is_simple_comapre = 1
	BEGIN
		SET @result = 1
		RETURN
	END
	
	IF OBJECT_ID('tempdb.dbo.#fields') IS NULL
	BEGIN
		-- Разбиваем строку @a_list
		CREATE TABLE #fields(
			field_name varchar(128))

		INSERT INTO #fields(
			field_name)
		SELECT Value FROM dbo.Utl_GetValueFromDelimitedStr (default, @a_list, default)
	END

  -- Сравниваем атрибут в цикле по списку атрибутов элемента в @xml и @xml2
  -- Если атрибут есть и в первом и во втором то сравниваем значения атрибутов
	-- количество артибутов элемента из @xml
	SET @cnt2=@is_simple_comapre
	WHILE @cnt2<2 BEGIN
		IF @cnt2=0 BEGIN
		  SET @x1=@xml2
		  SET @x2=@xml
		  SET @attCnt1 = @attCnt2
		END ELSE BEGIN
		  SET @x1=@xml
		  SET @x2=@xml2
		  SET @attCnt1 = @attCnt
		END

		SET @cnt = 1

		WHILE @cnt <= @attCnt1
		BEGIN
			SET @attName = NULL
			SET @attValue = NULL

			SET	@attName = @x1.value('local-name((/*/@*[sql:variable("@cnt")])[1])',  'varchar(max)')
			SET @attValue = @x1.value('(/*/@*[sql:variable("@cnt")])[1]', 'varchar(max)')

			-- check if the attribute exists in the other XML document
			IF @x2.exist('(/*/@*[local-name()=sql:variable("@attName")])[1]') = 0
			BEGIN
				SET @changed_alist = @changed_alist + @attName + ', '
				SET @result = 1
				IF @is_simple_comapre = 1 RETURN
			END

			IF  @x2.value('(/*/@*[local-name()=sql:variable("@attName")])[1]', 'varchar(max)') <> @attValue
			BEGIN
				IF(CHARINDEX(@attName,@changed_alist)=0) SET @changed_alist = @changed_alist + @attName + ', '
				SET @result = 1
			END

			SELECT @cnt = @cnt + 1
		END
		SET @cnt2=@cnt2+1
	END
	-- Сравниваем количество дочерних элементов 
	SET @elCnt = @xml.query('count(/*/*)').value('.','int')
	SET @elCnt2 = @xml2.query('count(/*/*)').value('.','int')

	IF  @elCnt <> @elCnt2
	BEGIN
		SET @result = 1
		RETURN
	END

	-- Рекурсивной вызов для сравнения дочерних элементов
	SET @cnt = 1
	SET @cnt2 = 1

	WHILE @cnt <= @elCnt
	BEGIN
		SELECT @x1 = @xml.query('/*/*[sql:variable("@cnt")]')

		WHILE @cnt2 <= @elCnt2
		BEGIN
			SET @x2 = @xml2.query('/*/*[sql:variable("@cnt2")]')

			EXEC prc_GL_CompareXMLAttributesValue
				@xml = @x1,
				@xml2 = @x2,
				@a_list = @a_list,
				@result = @result OUT,
				@changed_alist = @changed_alist OUT,
				@is_simple_comapre = @is_simple_comapre

			IF @result = 0 BREAK
			SELECT @cnt2 = @cnt2 + 1
		END

		SET @cnt2 = 1

		IF @result = 1
			RETURN

		SELECT @cnt = @cnt + 1
	END

END
GO
GRANT EXECUTE
    ON OBJECT::[dbo].[prc_GL_CompareXMLAttributesValue] TO PUBLIC
    AS [dbo];
