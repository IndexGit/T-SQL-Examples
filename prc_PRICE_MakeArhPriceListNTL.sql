CREATE PROCEDURE [dbo].[prc_PRICE_MakeArhPriceListNTL]
	@CalcDate smalldatetime = NULL,
	@MakeChange		bit = 0,	  	--	(0) - Не делать записей в архив (проверочный расчет) показывает ошибки violation of primary Key 
	@Debug 		    int = 0,		--	Параметр для отладки
	@Reset			bit = 0,		--	Отменить текущую работу процедуры рассчёта
	@ProductID int = NULL,			-- Для отладки пока
	@PricePolID int = NULL			-- Фильтр по прайсу
-------------------------------------------------------------------------------------
--	Процедура расчёта цен для слоёв по скидкам. Использовать для срабатывания проверок из процедуры
--	prc_PRICE_MakeArhPrice
-------------------------------------------------------------------------------------
--	Автор:	Мамонов А.В.
--	Модуль:	Цены 2.0 NTL
--	Дата:	21.11.2016
-------------------------------------------------------------------------------------
/*
-------------------------------------------------------------------------------------
	Логика процедуры рассчёта цен по NTL:
-------------------------------------------------------------------------------------
		1. Проверка запуска одним пользователем
		2. Проверки параметров системы
		3. Сбор всех скидок по прайсам и продуктам
		4. Учёт приоритета настроек скидок
		5. Исключить блокированные в прайс-листах продукты
		6. Сбор того что поменялось на расчётную дату:
			а. Новая БЦ
			b. Новая формула NTL
			c. Новый НДС продукта
			d. Смена НДС в прайс-листе???
			e. Новая скидка
			f. Конец скидки
			g. Новое исключение БЦ
			h. Окончание исключения БЦ
		7. Проверки отсутствия БЦ или НДС продукта
		8. Сбор параметров настройки скидки по слоям и разворот таблицы
		9. Расчёт цен по формуле в динамике
		10. Вызов процедуры рассчёта денег по слоям		
-------------------------------------------------------------------------------------		
	Варианты аналитик продукта:
	1.            Продукт
	2.            Бренд+Категория+МГП
	3.            Бренд+Категория 
	4.            Бренд+МГП
	5.            Категория+МГП
	6.            Бренд
	7.            Категория
	8.            МГП
-------------------------------------------------------------------------------------
	Посткриптум:
		При отмирании основной процедуры (prc_PRICE_MakeArhPrice) перенести логику проверок от туда

	Доделать:

		Добавить новую группировку продуктов
		Не вносить цену ещё раз, если ничего не поменялось в последний раз

	Цены могут не рассчитываться:
		1. Нет БЦ
		2. Нет НДС в справочнике ГП
		3. Нет действующей привязанной скидки
*/
-------------------------------------------------------------------------------------
--  Запуск:
/*
	DECLARE
		@CalcDate smalldatetime

	SET @CalcDate =  DATEADD(d,1,dbo.fnc_GL_GetDate())
--	select @CalcDate

	Exec [dbo].[prc_PRICE_MakeArhPriceListNTL] @CalcDate = '2017-06-15', @MakeChange = 1,@PricePolID = 507,  @Debug = 1, @ProductID = 2546

	Exec [dbo].[prc_PRICE_MakeArhPriceListNTL] @Reset = 1

	DECLARE @D smalldatetime
	SET @D = DATEADD(d,1,dbo.fnc_GL_GetDate())
	SET @D = '2017-01-01'

	Exec [dbo].[prc_PRICE_MakeArhPrice] '2017-06-15',1,1,NULL,942
*/
-------------------------------------------------------------------------------------
--	Изменения:
--		22.12.2016: Поправил конфликт цен в ArhPriceList и NewPriceList
--		23.12.2016: Поправил выбор привязки формулы блокировки
--		24.12.2016: Удаляем все расчитанные цены по новому и конфликтные старые на Дату
--		25.12.2016: Добавил параметр @PricePolID, оптимизация
--		27.12.2016: Игра с CTE, временными таблицами и поиск индексов, отключение МГП, НДС для каждого прайса свой
--		09.01.2017: Исправление НДС, ошибка с разблокировкой продуктов-аналогов
--		17.01.2017: Переход на MERGE ArhPriceList, Транзакция внутри Try-Catch, Оптимизация #GroupedPolProductSettings
--		18.01.2017: CTE для ArhPriceList TARGET в MERGE, удаление цены если она не отличалась от предыдущей в архиве
--		27.01.2017: Округление промо, занесение всех цен в архив, но только для тех продуктов, что менялись
--					Аналоги не учитываются для формулы блокировки, отмена удаления цены если она не отличалась от предыдущей в архиве
--					Блокировка продуктов без занесения в настройки скидок
--		06.04.2017: Учёт настроек МГП. Пересчёт продуктов без настроек по БЦ, учет аналогов в исключениях БЦ, разрешил проверочный расчёт предыдущих дат
--		17.05.2017: Патч. Убрал дублирование выбора БЦ в CTE. Вывод ошибок отрицательных цен. Очистка NewPriceList при боевом расчёте
--		22.05.2017: Нельзя чистить NewPriceList при боевом расчёте, т.к. таблица используется в prc_PRICE_MakeArhPrice
--		23.05.2017: Исключил давальческие продукты из аналогов в исключениях по БЦ
--		24.05.2017: Исключил заблокированне продукты в прайсе для выбора продуктов без настроек скидок, только по БЦ
--		14.06.2107: Разрешил расчёт для блокировки продукта в прайсе без БЦ и НДС
--		26.07.2017: Добавил блокированные в прайсе продукты для пересчёта и разблокировки без текущих настроек (C224309)
-------------------------------------------------------------------------------------
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE
		@CH char(2),
		@IntCount int,
		@Ret int,
		@ErrorMessage nvarchar(MAX)

	IF (@Reset = 0 AND @CalcDate IS NULL)
	BEGIN
		RAISERROR ('NTL. Неправельно заданы входные параметры!',16,1)
		RETURN 50001
	END

	SELECT
		@CH = CHAR(13) + CHAR(10), 
		@MakeChange = ISNULL(@MakeChange,0),
		@Debug = ISNULL(@Debug,0),
		@Reset = ISNULL(@Reset,0),
		@Ret = 0

	-- для запуска вручную, в клиенте не работает, т.к. оборачивается в транзакцию и ждёт
	IF (OBJECT_ID('tempdb..##prc_PRICE_MakeArhPriceListNTL') IS NOT NULL) 
	BEGIN
		IF(@Reset = 1)
		BEGIN
			GOTO DELETE_TEMP
		END

		DECLARE
			@GPID nvarchar(128),
			@sStartTime varchar(20)

		SELECT
			@GPID = GPID,
			@sStartTime = CONVERT(varchar(60),StartTime,104) + ' ' + CONVERT(varchar(60),StartTime,108)
		FROM
			##prc_PRICE_MakeArhPriceListNTL

		RAISERROR('NTL. Процедура уже запущена пользователем: %s в %s%sНеобходимо дождаться завершения расчёта пользователя или отменить его расчёт!',16,1,@GPID,@sStartTime,@CH)
		RETURN 50001

	END
	ELSE
	IF(@Reset = 1)
	BEGIN
		RAISERROR('NTL. Процедура никем не запущена на текущёи момент!',16,1)
		GOTO TO_FAIL
	END

	SELECT 
		dbo.Utl_GetRemoteUserName() as GPID,
		GETDATE() as StartTime
	INTO
		##prc_PRICE_MakeArhPriceListNTL
	
	DECLARE
		@CurrentLegalEntityID int,		-- Текущий филиал
		@CurrentSystemID int,			-- Текущая система
		@NTLFormula varchar(MAX),		-- формула NTL
		@PrecisionPrice		tinyint,	-- точность рассчета рублевой цены
		@FormulaBL1		int

	IF (OBJECT_ID('tempdb..#NTLResult') IS NULL) 
	CREATE TABLE #NTLResult(ID int IDENTITY(1,1),PScore varchar(255),ErrorMessage varchar(255))
	-- для сохранения записей при откате транзакции
	DECLARE @NTLResult TABLE(ID int IDENTITY(1,1),PScore varchar(255),ErrorMessage varchar(255))	

	IF (@CalcDate <= dbo.fnc_GL_GetDate() AND @MakeChange > 0)
	BEGIN
		RAISERROR ('NTL. Рассчитывать цены возможно только на дату начная с завтрашней!',16,1)
		GOTO TO_FAIL
	END
	-----------------------------------------------------------------------------------------------------------------------------	
	--Находим параметр с точностью рассчета
	-----------------------------------------------------------------------------------------------------------------------------
	SET 
		@PrecisionPrice = [dbo].[Cfg_GetParamOnDate]('PrecisionPrice', @CalcDate)

	IF 	@PrecisionPrice IS NULL 	
	BEGIN
		RAISERROR ('NTL. Не задан параметр настройки PrecisionPrice! Обратитесь в службу поддержки!',16,1)
		GOTO TO_FAIL
	END
	-----------------------------------------------------------------------------------------------------------------------------
	 
	SET @FormulaBL1 = dbo.Cfg_GetParamByNameF ('FormulaBL1', 0, 1)

	IF 	@FormulaBL1 IS NULL 	
	BEGIN
		RAISERROR ('NTL. Не задан параметр настройки FormulaBL1! Обратитесь в службу поддержки!',16,1)
		GOTO TO_FAIL
	END
	-----------------------------------------------------------------------------------------------------------------------------

	SET @NTLFormula = [dbo].[Cfg_GetParamOnDate]('FormulaNTL',@CalcDate)
	
	IF 	@NTLFormula IS NULL 	
	BEGIN
		RAISERROR ('NTL. Не задан параметр настройки NTLFormula! Обратитесь в службу поддержки!',16,1)
		GOTO TO_FAIL
	END	
	--SET @NTLFormula = 'BasePrice*(100-(L12+L13+L14+L25+L26+L27+L28+L29+L210+L211+L212+L213+L214))/100*(100-(L315+L316+L317+L318+L319+L320))/100*(100-(L422+L423+L424+L425+L426+L427+L428+L429+L430+L431+L432))/100'
	-----------------------------------------------------------------------------------------------------------------------------
/*
	-- Time statistic
	DECLARE @StartTime datetime, @EndTime datetime, @TotalTimeStr varchar(100)

	SET @StartTime = GETDATE() 

	
	INSERT INTO #NTLResult(PScore, ErrorMessage)
	SELECT
		'Запуск процедуры в', 
		CONVERT(varchar(60),@StartTime,104) + ' ' + CONVERT(varchar(60),@StartTime,108)
	UNION
	SELECT
		CASE @MakeChange WHEN 0 THEN 'ТЕСТОВЫЙ ' ELSE '' END + 'Расчёт цен', 
		'На дату: '+CONVERT(varchar(12),@CalcDate,104)
*/
	INSERT INTO #NTLResult(PScore, ErrorMessage)
	SELECT 'NTL. Запуск процедуры в ', CONVERT(varchar(60),GetDate(),104) + ' ' + CONVERT(varchar(60),GetDate(),108)

	SELECT 
		@CurrentLegalEntityID = dbo.Cfg_GetCurrentFirmID(),
		@CurrentSystemID = [dbo].[Cfg_GetCurrentSystemTypeID]()


	DECLARE
		@BPLayerID int,	-- слой для разницы БЦ
		@FixLayerID int	-- слой для фикс цены

	SELECT 
		@BPLayerID = DLayerID
	FROM
		c_PLDiscountLayer WITH(NOLOCK)
	WHERE
		DLayerStatus = 1 AND
		RowState = 1

	SELECT 
		@FixLayerID = DLayerID
	FROM
		c_PLDiscountLayer WITH(NOLOCK)
	WHERE
		DLayerStatus = 2 AND
		RowState = 1


	;WITH ForbidenLayers AS
	(
		SELECT
			'L' + CAST(g.DLayerGroupID as varchar(2))+CAST(l.DLayerID as varchar(2)) as LayerNumber			
		FROM
			[dbo].[c_PLDiscountLayerGroup] g WITH(NOLOCK)
			INNER JOIN [dbo].[c_PLDiscountLayer] l WITH(NOLOCK) ON
				l.DLayerGroupID = g.DLayerGroupID
				AND l.DLayerID IN (@FixLayerID,@BPLayerID)
		WHERE
			l.RowState = 1 AND
			g.RowState = 1
	)
	SELECT 
		1 as Error
	INTO #Check -- Нельзя использовать CTE в подзапросах (выражениях IF EXISTS)
	FROM
		ForbidenLayers f
	WHERE
		CHARINDEX(f.LayerNumber,@NTLFormula) > 0

	IF @@ROWCOUNT > 0
	BEGIN
		RAISERROR ('NTL. Нельзя использовать дефолтные слои в формуле расчёта цен! Необходимо изменить формулу (параметр FormulaNTL) или переназначить дефолтные слои (Тип слоя)',16,1)
		GOTO TO_FAIL
	END	
	
	IF (OBJECT_ID('tempdb..#ActualRef') IS NULL) 
	BEGIN
		-- актуальные привязки формул на дату
		CREATE TABLE #ActualRef 
		(
			ProductID int NOT NULL,
			PolType int NOT NULL,
			PLFormula int NOT NULL,
			IsNow int NOT NULL,
			CONSTRAINT PK_ActualRef PRIMARY KEY CLUSTERED 
			(
				ProductID ASC,
				PolType ASC
			)
		)

		CREATE NONCLUSTERED INDEX IX_ActualRef_PLFormula1 ON #ActualRef
		([PLFormula])
		INCLUDE ([ProductID],[PolType],[IsNow])

		CREATE NONCLUSTERED INDEX IX_ActualRef_PLFormula2 ON #ActualRef
		([IsNow],[PLFormula])
		INCLUDE ([ProductID],[PolType])

		;WITH refNow AS
		(
			SELECT
				a1.ProductID,
				a1.PolType,
				MAX(a1.Data) as MAXData
			FROM
				PLFormulaRefArh a1
			WHERE
				a1.FormulaType = 0 AND
				a1.Data <= @CalcDate
				AND (@PricePolID IS NULL OR a1.PolType = @PricePolID)
			GROUP BY
				a1.ProductID,a1.PolType
		)
		INSERT INTO #ActualRef(ProductID,PolType,PLFormula,IsNow)
		SELECT
			n.ProductID, 
			n.PolType,
			a.PLFormula,
			CASE n.MAXData WHEN @CalcDate THEN 1 ELSE 0 END as IsNow -- привязка на дату расчета или ранее
		FROM
			refNow n
			INNER JOIN PLFormulaRefArh a ON
				a.ProductID = n.ProductID
				AND a.PolType = n.PolType
				AND a.Data = n.MAXData
				AND a.FormulaType = 0
	END

	IF(@Debug BETWEEN 1 AND 3)
	BEGIN
		SELECT '#ActualRef'
		SELECT
			*
		FROM
			#ActualRef
		WHERE
			(@PricePolID IS NULL OR PolType = @PricePolID) AND
			(@ProductID IS NULL OR ProductID = @ProductID)
		ORDER BY
			PolType,ProductID
	END

	------------------------------------------------------------------------------------------------------------
	-- собираем все актуальные на дату скидки по прайсам
	------------------------------------------------------------------------------------------------------------

	CREATE TABLE #SettingsInDate 
	(
		DSettingID int NOT NULL,
		PricePolID int NOT NULL,
		ProductID int NULL,
		BrandID int NULL,
		CategoryID int NULL,
		MGID int NULL,
		IsDiscountEnd bit NOT NULL,
		CONSTRAINT PK_SettingsInDate PRIMARY KEY CLUSTERED 
		(
			DSettingID ASC,
			PricePolID ASC
		)
	)
	CREATE INDEX IX_SettingsInDate_ProductAnalitics ON #SettingsInDate
	(
		ProductID,
		BrandID,
		CategoryID,
		MGID 
	)


	INSERT INTO #SettingsInDate(DSettingID,PricePolID,ProductID,BrandID,CategoryID,MGID,IsDiscountEnd)
	SELECT 
		s.DSettingID,
		s.PricePolID,
		s.ProductID,
		s.BrandID,
		s.CategoryID,
		s.MGID,
		CASE 
			WHEN @CalcDate = DATEADD(d,1,s.DateEnd)
				THEN 1
			ELSE 0
		END as IsDiscountEnd		
	FROM
		[dbo].[PLDiscountSettings] s
		INNER JOIN PricePol p WITH(NOLOCK) ON
			p.PricePolID = s.PricePolID
			AND ISNULL(p.NTLStartDate,65535) <= @CalcDate			-- Дата NTL наступила по прайсу
	WHERE
		-- текущая дата в периоде действия скидки, или скидка закончила действие за день до расчёта
		@CalcDate BETWEEN s.DateBegin AND DATEADD(d,1,s.DateEnd) AND 
		(@PricePolID IS NULL OR s.PricePolID = @PricePolID)

	IF(@Debug BETWEEN 1 AND 3)
	BEGIN
		SELECT '#SettingsInDate'
		SELECT
			*
		FROM
			#SettingsInDate
		WHERE
			@PricePolID IS NULL OR PricePolID = @PricePolID
	END


	CREATE TABLE #SettingsProductList 
	(
		PricePolID int,
		ProductID int,
		DSettingID int
	)

	CREATE NONCLUSTERED INDEX IX_SettingsProductList ON #SettingsProductList
		([PricePolID],[ProductID])
		INCLUDE (DSettingID)

	------------------------------------------------------------------------------------------------------------
	--	По категории
	------------------------------------------------------------------------------------------------------------
	;WITH CategorySettings AS
	(
		SELECT 
			CASE IsDiscountEnd
				WHEN 0 THEN DSettingID
				ELSE 0
			END as DSettingID,
			PricePolID,
			CategoryID
		FROM
			#SettingsInDate c
		WHERE
			ProductID IS NULL AND
			CategoryID IS NOT NULL AND
			BrandID IS NULL AND
			MGID IS NULL
	)
	,CategoryAndBrandSettings AS
	(
		SELECT 
			CASE IsDiscountEnd
				WHEN 0 THEN DSettingID
				ELSE 0
			END as DSettingID,
			PricePolID,
			BrandID,
			CategoryID
		FROM
			#SettingsInDate c
		WHERE
			ProductID IS NULL AND
			CategoryID IS NOT NULL AND
			BrandID IS NOT NULL AND
			MGID IS NULL

	),
	------------------------------------------------------------------------------------------------------------
	--	По Бренду
	------------------------------------------------------------------------------------------------------------
	BrandSettings AS
	(
		SELECT 
			CASE IsDiscountEnd
				WHEN 0 THEN DSettingID
				ELSE 0
			END as DSettingID,
			PricePolID,
			BrandID
		FROM
			#SettingsInDate c
		WHERE
			ProductID IS NULL AND
			BrandID IS NOT NULL AND
			CategoryID IS NULL AND
			MGID IS NULL
	),
	MGPSettings AS
	( 
		SELECT 
			CASE IsDiscountEnd
				WHEN 0 THEN DSettingID
				ELSE 0
			END as DSettingID,
			PricePolID,
			MGID			
		FROM
			#SettingsInDate s
		WHERE
			ProductID IS NULL AND
			BrandID IS NULL AND
			CategoryID IS NULL AND
			MGID IS NOT NULL
	),
	-- список настроек МГП на дату
	allMG AS
	(
		SELECT
			MGID
		FROM
			#SettingsInDate s
		WHERE 
			MGID IS NOT NULL
		GROUP BY
			MGID
	),
	allCategoryInSettings AS
	(
		SELECT
			CategoryID
		FROM
			#SettingsInDate s
		WHERE
			CategoryID IS NOT NULL
		GROUP BY
			CategoryID
	),
	allCategory AS
	(
		SELECT
			sc.CategoryID,cg.CategoryID as ParentCategoryID
		FROM
			c_ProductCategories cg WITH(NOLOCK)
			INNER JOIN c_ProductCategories c WITH(NOLOCK)
				ON c.ParentID = cg.CategoryID
				AND c.[State] = 1
			INNER JOIN c_ProductCategories sc WITH(NOLOCK)
				ON sc.ParentID = c.CategoryID
				AND sc.[State] = 1
			INNER JOIN allCategoryInSettings s ON
				s.CategoryID = cg.CategoryID
		WHERE
			cg.[Level] = 2 AND
			cg.[State] = 1
		UNION
		SELECT
			sc.CategoryID,c.CategoryID as ParentCategoryID
		FROM
			c_ProductCategories c WITH(NOLOCK)
			INNER JOIN c_ProductCategories sc WITH(NOLOCK)
				ON sc.ParentID = c.CategoryID
				AND sc.[State] = 1
			INNER JOIN allCategoryInSettings s ON
				s.CategoryID = c.CategoryID
		WHERE
			c.[Level] = 3 AND
			c.[State] = 1
		UNION
		SELECT
			sc.CategoryID,sc.CategoryID as ParentCategoryID
		FROM
			c_ProductCategories sc WITH(NOLOCK)
			INNER JOIN allCategoryInSettings s ON
				s.CategoryID = sc.CategoryID
		WHERE
			sc.Level = 4 AND
			sc.[State] = 1
	),
	allBrandInSettings AS
	(
		SELECT
			BrandID
		FROM
			#SettingsInDate s
		WHERE
			BrandID IS NOT NULL
		GROUP BY
			BrandID
	),
	allBrand AS
	(
		SELECT
			b.BrandID,bg.BrandID as ParentBrandID
		FROM
			c_Brands bg WITH(NOLOCK)
			INNER JOIN	c_Brands b WITH(NOLOCK) ON
				b.ParentID = bg.BrandID
				AND b.[State] = 1
			INNER JOIN allBrandInSettings s ON
				s.BrandID = bg.BrandID
		WHERE
			bg.[Level] = 1 AND
			bg.[State] = 1
		UNION
		SELECT
			b.BrandID,b.BrandID as ParentBrandID
		FROM
			c_Brands b WITH(NOLOCK)
			INNER JOIN allBrandInSettings s ON
				s.BrandID = b.BrandID
		WHERE
			b.[Level] = 2 AND
			b.[State] = 1
	),
	-- параметры настроек МГП на дату
	MGSettings as 
	(	
		SELECT 
			s.MGID,s.MGPID,s.BrandID,s.CategoryID,s.RowType
		FROM
			allMG 
			INNER JOIN [c_PLMarketGroupSettings] s WITH(NOLOCK) ON
				allMG.MGID = s.MGID
		WHERE
			@CalcDate BETWEEN s.DateStart AND ISNULL(s.DateEnd,@CalcDate)
	),
	-- список настроек
	AllMGP as 
	(
		SELECT
			MGPID
		FROM
			MGSettings
		GROUP BY
			MGPID
	),
	-- МГП переводим в продукты
	MGPToProducts AS
	(
		SELECT
			s.MGPID,
			pEx.ProductID
		FROM
			AllMGP s
			INNER JOIN c_ProdMarketGroups mgp WITH(NOLOCK) ON
				mgp.MGPID = s.MGPID
				AND mgp.[Status] = 1
			LEFT JOIN c_Brands b WITH(NOLOCK) ON
				b.MGPID = s.MGPID
			LEFT JOIN c_ProductCategories sc WITH(NOLOCK) ON
				sc.MGPID = s.MGPID
			LEFT JOIN  c_UnsecuredProducts	u WITH(NOLOCK)	ON
				u.CategoryID = sc.CategoryID			
			INNER JOIN c_Products pEx WITH(NOLOCK) ON
				pEx.ExceptionMGPID = s.MGPID OR
				(pEx.ExceptionMGPID IS NULL AND b.BrandID = pEx.BrandID) OR
				(pEx.ExceptionMGPID IS NULL AND b.MGPID IS NULL AND u.UnsecuredProductID = pEx.UnsecuredProductID)
		GROUP BY
			s.MGPID,pEx.ProductID
	),
	-- настройки МГП переводим в продукты
	MGToProducts as
	(
		SELECT 
			sIncl.MGID, mpIncl.ProductID
		FROM
			-- включить по аналитикам
			MGSettings sIncl
			INNER JOIN MGPToProducts mpIncl WITH(NOLOCK) ON
				sIncl.MGPID = mpIncl.MGPID
			INNER JOIN c_Products p WITH(NOLOCK) ON
				p.ProductID = mpIncl.ProductID
				AND (sIncl.BrandID IS NULL OR p.BrandID = sIncl.BrandID)			-- По Бренду
			INNER JOIN c_UnsecuredProducts up WITH(NOLOCK) ON
				up.UnsecuredProductID = p.UnsecuredProductID
				AND (sIncl.CategoryID IS NULL OR up.CategoryID = sIncl.CategoryID)	-- По Категории
			-- исключить по аналитикам
			LEFT JOIN MGSettings sExc ON
				sExc.MGID = sIncl.MGID
				AND sExc.MGPID = sIncl.MGPID
				AND sExc.RowType = 2 -- Исключить
			LEFT JOIN MGPToProducts mpExc WITH(NOLOCK) ON
				sExc.MGPID = mpExc.MGPID											-- Та же МГП
				AND mpExc.ProductID = mpIncl.ProductID								-- Тот же продукт в МГП
				AND (sExc.BrandID IS NULL OR p.BrandID = sExc.BrandID)				-- По Бренду
				AND (sExc.CategoryID IS NULL OR up.CategoryID = sExc.CategoryID)	-- По Категории
		WHERE
			sIncl.RowType = 1 AND				-- Включить
			mpExc.ProductID IS NULL 			-- Исключение по  Бренду и Категории

	)
	-- все собранные продукты
		INSERT INTO #SettingsProductList(DSettingID,PricePolID,ProductID )
		-- По Категории
		SELECT 
			DSettingID,
			PricePolID,
			p.ProductID
		FROM
			CategorySettings s
			INNER JOIN allCategory ac ON
				ac.ParentCategoryID = s.CategoryID
			INNER JOIN c_UnsecuredProducts	u WITH(NOLOCK)	ON
				u.CategoryID = ac.CategoryID
			INNER JOIN c_Products p WITH(NOLOCK) ON
				p.UnsecuredProductID = u.UnsecuredProductID
		WHERE
			p.Tara = 0 AND
			p.[State] = 1
--			StateGSP ?
		UNION ALL
		-- По Бренду
		SELECT 
			DSettingID,
			PricePolID,
			ProductID
		FROM
			BrandSettings s
			INNER JOIN allBrand ab ON
				ab.ParentBrandID = s.BrandID
			INNER JOIN c_Products p WITH(NOLOCK) ON
				p.BrandID = ab.BrandID
		WHERE
			p.Tara = 0 AND
			p.[State] = 1
--			StateGSP ?	
		UNION ALL	
		-- По продукту
		SELECT 
			CASE IsDiscountEnd
				WHEN 0 THEN c.DSettingID
				ELSE 0
			END as DSettingID,
			c.PricePolID,
			c.ProductID
		FROM
			#SettingsInDate c
		WHERE
			c.ProductID IS NOT NULL
		UNION ALL
		-- По Бренду и Категории
		SELECT
			s.DSettingID,
			s.PricePolID,
			p.ProductID
		FROM
			CategoryAndBrandSettings s
			INNER JOIN allCategory ac ON
				ac.ParentCategoryID = s.CategoryID
			INNER JOIN allBrand ab ON
				ab.ParentBrandID = s.BrandID
			INNER JOIN  c_UnsecuredProducts	u WITH(NOLOCK)	
				ON ac.CategoryID = u.CategoryID
			INNER JOIN c_Products p WITH(NOLOCK) ON
				p.UnsecuredProductID = u.UnsecuredProductID
				AND ab.BrandID = p.BrandID

		UNION ALL 
		--	по МГП
		SELECT
			s.DSettingID,
			s.PricePolID,
			mp.ProductID
		FROM
			MGPSettings s
			INNER JOIN MGToProducts mp ON
				mp.MGID = s.MGID



	CREATE TABLE #BlockedPriceProd
	(
		PricePolID int NOT NULL,
		ProductID int NOT NULL,
		BlockNow int NOT NULL,
		CONSTRAINT PK_BlockedPriceProd PRIMARY KEY CLUSTERED 
		(
			PricePolID ASC,
			ProductID ASC
		)
	)

	INSERT INTO #BlockedPriceProd
	SELECT
		PolType as PricePolID,
		ProductID,
		r.IsNow as BlockNow
	FROM
		#ActualRef r 
	WHERE
		r.PLFormula = @FormulaBL1
	
	IF(@Debug BETWEEN 1 AND 3)
	BEGIN
		SELECT '#BlockedPriceProd'
		SELECT
			*
		FROM
			#BlockedPriceProd
		WHERE
			(@PricePolID IS NULL OR PricePolID = @PricePolID) AND
			(@ProductID IS NULL OR ProductID = @ProductID)
		ORDER BY
			PricePolID,ProductID
	END

	CREATE TABLE #allPolProductSettings
	(
		PricePolID int NOT NULL,
		ProductID int NOT NULL,
		DSettingID int NOT NULL,
		BlockNow int NOT NULL,
		CONSTRAINT PK_allPolProductSettings PRIMARY KEY CLUSTERED 
		(
			PricePolID ASC,
			ProductID ASC,
			DSettingID ASC
		)
	)

	-- Список продуктов по прайсам  с учётом аналогов и заблокированных в пл
	INSERT INTO #allPolProductSettings
	SELECT
		a.PricePolID,
		ap.ProductID,
		a.DSettingID,
		MAX(ISNULL(bpp.BlockNow,0)) as BlockNow
	FROM
		#SettingsProductList a
		CROSS APPLY dbo.fnc_GL_GetAnalogProductID(a.ProductID) as ap
		INNER JOIN Products p WITH(NOLOCK) ON
			p.ID = ap.ProductID
		LEFT JOIN #BlockedPriceProd bpp					-- привязка блокировки по аналогам
			ON bpp.PricePolID = a.PricePolID
			AND bpp.ProductID = ap.ProductID
	WHERE
		((bpp.BlockNow = 1 AND ap.IsAnalog = 0) OR bpp.PricePolID IS NULL) AND	-- учитывается только блокировка на дату расчёта не по аналогам
		ap.Discont = 0 AND			-- НЕ блокированный в ГП
		p.[Status] & 512 = 0 AND	-- НЕ Давальческий 
		p.ID = p.ProdID AND			-- НЕ фасованный
		p.Tara = 0					-- НЕ тара
	GROUP BY
		a.PricePolID,
		ap.ProductID,
		a.DSettingID

	--	Блокировка продуктов без занесения в настройки скидок
	UNION
	SELECT
		b.PricePolID,
		b.ProductID,
		0 as DSettingID,
		1 as BlockNow
	FROM
		#BlockedPriceProd b
		-- только для прайсов по NTL
		INNER JOIN PricePol p WITH(NOLOCK) ON
			p.PricePolID = b.PricePolID
			AND p.NTLStartDate <= @CalcDate
	WHERE
		BlockNow = 1


	----------------------------------------------------------------------------------------
	-- Заносим продукты без настроек скидок
	----------------------------------------------------------------------------------------
	;WITH 
	-- те что уже есть
	ExistsPolProducts AS
	(
		SELECT
			PricePolID,
			ProductID
		FROM
			#allPolProductSettings
		GROUP BY
			PricePolID,
			ProductID
	),
	-- Продукты бывшие в архиве
	LastArhPriceDate AS
	(
		SELECT
			a.PolType,
			a.ProductID,
			MAX(a.Data) as Data,
			a.PriceType
		FROM
			ArhPriceList a WITH(NOLOCK)
			-- только для прайсов по NTL
			INNER JOIN PricePol p WITH(NOLOCK) ON
				p.PricePolID = a.PolType
				AND p.NTLStartDate <= @CalcDate
			-- список настроек скидок
			LEFT JOIN ExistsPolProducts e ON
				e.PricePolID = a.PolType
				AND e.ProductID = a.ProductID
		WHERE
			a.Data <= @CalcDate AND
			(@PricePolID IS NULL OR a.PolType = @PricePolID) AND
			(@ProductID IS NULL OR a.ProductID = @ProductID) AND
			e.ProductID IS NULL -- нет в настройках
		GROUP BY
			a.PolType,
			a.ProductID,
			a.PriceType
	)
	INSERT INTO #allPolProductSettings
	SELECT
		l.PolType as PricePolID,
		l.ProductID,
		0 as DSettingID,
		0 as BlockNow		
	FROM
		LastArhPriceDate l
		INNER JOIN ArhPriceList a WITH(NOLOCK) ON
			a.ProductID = l.ProductID
			AND a.PolType = l.PolType
			AND a.Data = l.Data
			AND a.PriceType = l.PriceType
		LEFT JOIN #BlockedPriceProd bpp					-- проверка привязки блокировки 
			ON bpp.PricePolID = l.PolType
			AND bpp.ProductID = l.ProductID
	WHERE
--		a.[Status] & 4 = 0 AND			-- те что не заблокированы по прайсу
--		возможно их как раз надо разблокировать без настроек, по привязке формулы
		bpp.ProductID IS NULL	-- не блокированные в прайсе


	IF(@Debug IN (1,2))
	BEGIN
		SELECT '#allPolProductSettings'
		SELECT
			*
		FROM
			#allPolProductSettings
		WHERE
			(@PricePolID IS NULL OR PricePolID = @PricePolID) AND
			(@ProductID IS NULL OR ProductID = @ProductID)
		ORDER BY
			PricePolID,ProductID,DSettingID desc
	END

	-- список продукт-прайс
	SELECT 
		PricePolID,ProductID,MAX(BlockNow) as BlockNow
	INTO
		#PolProductList
	FROM
		#allPolProductSettings
	GROUP BY
		PricePolID,ProductID

	------------------------------------------------------------------------------------------------------------
	--	Сбор данных которые меняются завтра
	------------------------------------------------------------------------------------------------------------
	--	ЕСЛИ менялись Базовые цены
	------------------------------------------------------------------------------------------------------------
	SELECT
		pl.PricePolID,
		pl.ProductID,
		'Новая БЦ' as ChangeBy,
		NULL as DSettingID
	INTO 
		#PriceProdChanged
	FROM 
		le_PLBasePrice bp WITH(NOLOCK)
		LEFT JOIN PricePol pp WITH(NOLOCK) ON
			pp.BasePriceTypeID = bp.BasePriceTypeID
			AND pp.[Status] & 128 = 0
		INNER JOIN #PolProductList pl ON
			pl.ProductID = bp.ProductID
	WHERE	
		(bp.BasePriceTypeID = 1 OR pp.BasePriceTypeID IS NOT NULL) AND -- тип БЦ = 1 (филиальный) или тот что в прайсе
		bp.DatePrice = @CalcDate AND
		bp.LegalEntityID = @CurrentLegalEntityID
	GROUP BY
		pl.PricePolID,
		pl.ProductID	
	UNION
	------------------------------------------------------------------------------------------------------------
	--	ЕСЛИ менялась формула
	------------------------------------------------------------------------------------------------------------
	SELECT
		PricePolID,
		ProductID,
		'Новая формула',
		NULL as DSettingID
	FROM
		#PolProductList
	WHERE
		EXISTS
		--	 Формула меняется с завтрашнего дня
		(
			SELECT 1
			FROM
				Cfg_Params p WITH(NOLOCK)
				INNER JOIN Cfg_ParamValuesRepl v WITH(NOLOCK) ON
					p.ParamID = v.ParamID
			WHERE
				p.ParamName = 'FormulaNTL' AND
				v.DateFrom = @CalcDate AND
				v.SystemID = @CurrentSystemID
		)
	GROUP BY
		PricePolID,
		ProductID
	UNION
	------------------------------------------------------------------------------------------------------------
	--	Если занесена новая привязка формулы блокировки
	------------------------------------------------------------------------------------------------------------
	SELECT
		p.PricePolID,
		p.ProductID,
		'Новая блокировка продукта',
		NULL as DSettingID
	FROM
		#PolProductList p
		INNER JOIN #BlockedPriceProd r ON
			r.ProductID = p.ProductID
			AND p.PricePolID = r.PricePolID
			AND r.BlockNow = 1
	UNION
	------------------------------------------------------------------------------------------------------------
	--	Если занесена новая привязка формулы блокировки
	------------------------------------------------------------------------------------------------------------
	SELECT
		r.PolType,
		r.ProductID,
		'Новая привязка продукта',
		NULL as DSettingID
	FROM
		#PolProductList p
		INNER JOIN #ActualRef r ON
			r.ProductID = p.ProductID
			AND p.PricePolID = r.PolType
			AND r.PLFormula <> @FormulaBL1 
			AND r.IsNow = 1
	UNION
	------------------------------------------------------------------------------------------------------------
	-- ЕСЛИ Менялся НДС в Справочнике продуктов ГП
	------------------------------------------------------------------------------------------------------------
	SELECT 
		pl.PricePolID,
		pl.ProductID,
		'Новый НДС',
		NULL as DSettingID
	FROM	
		PricePol AS pp WITH(NOLOCK)
		INNER JOIN #PolProductList pl 
			ON pl.PricePolID = pp.PricePolID		
		INNER JOIN ArhStatusProd AS asp WITH(NOLOCK)
			ON asp.ProdID = pl.ProductID
			AND asp.Data = @CalcDate
	WHERE
		(@PricePolID IS NULL OR pl.PricePolID = @PricePolID) AND
		pp.NDS IS NULL -- НДС из прайслиста
		AND pp.[Status] & 128 = 0
	GROUP BY
		pl.PricePolID,
		pl.ProductID	
	UNION
	------------------------------------------------------------------------------------------------------------
	--	Если были занесены новые скидки на завтра
	------------------------------------------------------------------------------------------------------------
	SELECT 
		d.PricePolID,
		NULL as ProductID,	-- все продукты
		'Новая скидка',
		DSettingID			-- по скидке
	FROM
		[dbo].[PLDiscountSettings] d
	WHERE
		(@PricePolID IS NULL OR PricePolID = @PricePolID) AND
		DateBegin = @CalcDate
	GROUP BY
		d.PricePolID,
		d.DSettingID
	UNION
	------------------------------------------------------------------------------------------------------------
	--	Если закончивается скидка
	------------------------------------------------------------------------------------------------------------
	SELECT 
		d.PricePolID,
		NULL as ProductID,	-- все продукты
		'Конец скидки',
		d.DSettingID			-- по скидке
	FROM
		[dbo].[PLDiscountSettings] d
	WHERE
		(@PricePolID IS NULL OR PricePolID = @PricePolID) AND
		d.DateEnd = DATEADD(d,-1,@CalcDate)
	GROUP BY
		d.PricePolID,
		d.DSettingID
	UNION
	------------------------------------------------------------------------------------------------------------
	--	Если занесены новые исключения по БЦ на дату расчета
	------------------------------------------------------------------------------------------------------------
	SELECT
		ex.PricePolID,
		ex.ProductID,
		'Новое исключение БЦ',
		NULL as DSettingID
	FROM
		[dbo].[PLDiscountExceptionSettings] ex
	WHERE
		(@PricePolID IS NULL OR PricePolID = @PricePolID) AND
		ex.DateBegin = @CalcDate AND
		ex.RowState = 1
	GROUP BY
		ex.PricePolID,
		ex.ProductID
	UNION
	------------------------------------------------------------------------------------------------------------
	--	Если заканчивается исключения по БЦ на дату расчета
	------------------------------------------------------------------------------------------------------------
	SELECT
		ex.PricePolID,
		ex.ProductID,
		'Закончилось исключение БЦ',
		NULL as DSettingID
	FROM
		[dbo].[PLDiscountExceptionSettings] ex
	WHERE
		(@PricePolID IS NULL OR PricePolID = @PricePolID) AND
		ex.DateEnd = DATEADD(d,-1,@CalcDate) AND
		ex.RowState = 1
	GROUP BY
		ex.PricePolID,
		ex.ProductID

	------------------------------------------------------------------------------------------------------------

	IF(@Debug BETWEEN 1 AND 3)
	BEGIN
		SELECT '#PriceProdChanged'
		SELECT 
			*
		FROM
			#PriceProdChanged
		WHERE
			(@PricePolID IS NULL OR PricePolID = @PricePolID) AND
			(@ProductID IS NULL OR ProductID = @ProductID)
		ORDER BY
			PricePolID,
			ProductID
	END

	INSERT INTO #NTLResult(PScore, ErrorMessage)
	SELECT
		'NTL. Найдены изменения',
		ChangeBy + ': ' + CAST(COUNT(*) as varchar(4))
	FROM
		#PriceProdChanged
	GROUP BY
		ChangeBy


	CREATE TABLE #CalcProductList
	(
		PricePolID int NOT NULL,
		ProductID int NOT NULL,
		IsBlock int NOT NULL,

		CONSTRAINT PK_CalcProductList PRIMARY KEY CLUSTERED 
		(
			PricePolID ASC,
			ProductID ASC
		)
	)

	------------------------------------------------------------------------------------------------------------
	--	Ищем продукты, для которых что-то поменялось
	------------------------------------------------------------------------------------------------------------
	INSERT INTO #CalcProductList	
	SELECT 
		l.PricePolID,
		l.ProductID,
		MAX(l.BlockNow) as IsBlock -- блокировка продукта
	FROM
		-- все продукты по скидкам
		#allPolProductSettings l	
		-- те что поменялись на дату по прайсу			
		INNER JOIN #PriceProdChanged e ON
			e.PricePolID = l.PricePolID
			AND l.ProductID = ISNULL(e.ProductID,l.ProductID)
			AND (l.DSettingID = 0 OR l.DSettingID = ISNULL(e.DSettingID,l.DSettingID)) -- конец скидки или по конкретной скидке
		-- исключим заблокированные прайс-листы
		INNER JOIN PricePol pp WITH(NOLOCK)
			ON pp.PricePolID = l.PricePolID
			AND pp.[Status] & 128 = 0
	GROUP BY
		l.PricePolID,
		l.ProductID
	

	IF (@Debug IN (1,2))
	BEGIN
		SELECT '#CalcProductList'
		SELECT 
			* 
		FROM 
			#CalcProductList 
		WHERE
			(@PricePolID IS NULL OR PricePolID = @PricePolID) AND
			(@ProductID IS NULL OR ProductID = @ProductID)
		ORDER BY 
			PricePolID, ProductID
	END

	IF EXISTS(SELECT TOP 1 1 FROM #CalcProductList)
	INSERT INTO #NTLResult(PScore, ErrorMessage)
	SELECT 
		'NTL. Найдено продуктов:',
		COUNT(DISTINCT ProductID)
	FROM
		#CalcProductList nds
		
	-- список подобранных скидок по слоям 
	CREATE TABLE #GroupedPolProductSettings
	(
		PricePolID int NOT NULL,
		ProductID int NOT NULL,
		DSettingID bigint NOT NULL,
		DLayerID int NOT NULL,
		DiscountPercent decimal(8,4) NULL,
		CONSTRAINT PK_GroupedPolProductSettings PRIMARY KEY CLUSTERED 
		(
			PricePolID ASC,
			ProductID ASC,
			DSettingID ASC,
			DLayerID ASC
		)
	)
	CREATE INDEX #ix_GroupedPolProductSettings_PolProduct ON #GroupedPolProductSettings
	(
		PricePolID ASC,
		ProductID ASC
	) WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON) ON [PRIMARY]

	CREATE INDEX #ix_GroupedPolProductSettings_Dlayer ON #GroupedPolProductSettings
	(
		[DLayerID]
	)
	INCLUDE ([PricePolID],[ProductID],[DSettingID],[DiscountPercent])


	------------------------------------------------------------------------------------------------------------
	--	Подбираем фикс цену по приоритету
	------------------------------------------------------------------------------------------------------------
	;WITH allProductLayerSettings AS
	(
		SELECT 
			a.PricePolID,a.ProductID,ds.DSettingID,ds.FixPrice
		FROM
			#allPolProductSettings a
			INNER JOIN #CalcProductList с WITH(NOLOCK) ON	-- те что поменялись
				с.PricePolID = a.PricePolID
				AND с.ProductID = a.ProductID
			INNER JOIN [dbo].[PLDiscountSettings] ds WITH(NOLOCK) ON
				ds.DSettingID = a.DSettingID
		WHERE
			ds.FixPrice >= 0
		GROUP BY
			a.PricePolID,
			a.ProductID,
			ds.DSettingID,
			ds.FixPrice
	),
	-- находим фикс цену по приоритету для прайса-продукта
	maxPolProductFix as
	(
		SELECT
			PricePolID,
			ProductID,
			MAX(DSettingID) as maxDSettingID	-- последняя скидка для фикс цены
		FROM
			allProductLayerSettings
		GROUP BY
			PricePolID,ProductID
	)
	-- находим последнее значение фикс цены
	SELECT
		a.PricePolID,
		a.ProductID,
		a.DSettingID,
		a.FixPrice
	INTO 
		#GroupedPolProductFixSettings
	FROM
		maxPolProductFix m
		INNER JOIN allProductLayerSettings a ON
			a.PricePolID = m.PricePolID
			AND a.ProductID = m.ProductID
			AND a.DSettingID = m.maxDSettingID
	WHERE
		a.FixPrice > 0


	IF(@Debug IN (1,2))
	BEGIN
		SELECT '#GroupedPolProductFixSettings'
		SELECT 
			* 
		FROM 
			#GroupedPolProductFixSettings
		WHERE
			(@PricePolID IS NULL OR PricePolID = @PricePolID) AND
			(@ProductID IS NULL OR ProductID = @ProductID)
		ORDER BY
			PricePolID,ProductID
	END

	------------------------------------------------------------------------------------------------------------
	--	Подбираем слои по приоритету
	------------------------------------------------------------------------------------------------------------

	;WITH maxPolProductLayer AS
	(
		SELECT 
			a.PricePolID,
			a.ProductID,
			dls.DLayerID,
			MAX(ds.DSettingID) as DSettingID
		FROM
			#allPolProductSettings a
			INNER JOIN #CalcProductList с WITH(NOLOCK) ON	-- те что поменялись
				с.PricePolID = a.PricePolID
				AND с.ProductID = a.ProductID
			INNER JOIN [dbo].[PLDiscountSettings] ds WITH(NOLOCK) ON
				ds.DSettingID = a.DSettingID
				AND ISNULL(ds.FixPrice,0) = 0				-- отмена фикса или его нет
			-- слоёв может и не быть
			LEFT JOIN [dbo].[PLDiscountLayerSettings] dls WITH(NOLOCK) ON
				dls.DSettingID = a.DSettingID
		GROUP BY
			a.PricePolID,a.ProductID,dls.DLayerID
	)
	-- итоговая сгруппированная выборка
	INSERT INTO #GroupedPolProductSettings
	SELECT 
		m.PricePolID,m.ProductID,m.DSettingID,ISNULL(m.DLayerID,0),dls.DiscountPercent
	FROM
		maxPolProductLayer m
		LEFT JOIN [dbo].[PLDiscountLayerSettings] dls WITH(NOLOCK) ON
				dls.DSettingID = m.DSettingID
				AND dls.DLayerID = m.DLayerID
		-- нет в фикс ценах
		LEFT JOIN #GroupedPolProductFixSettings f ON
			f.PricePolID = m.PricePolID
			AND f.ProductID = m.ProductID
	WHERE
		f.ProductID IS NULL
	GROUP BY
		m.PricePolID,m.ProductID,m.DSettingID,m.DLayerID,dls.DiscountPercent	
	
	IF(@Debug IN (1,2))
	BEGIN
		SELECT '#GroupedPolProductSettings'
		SELECT 
			* 
		FROM 
			#GroupedPolProductSettings
		WHERE
			(@PricePolID IS NULL OR PricePolID = @PricePolID) AND
			(@ProductID IS NULL OR ProductID = @ProductID)
		ORDER BY
			PricePolID,ProductID
	END


	------------------------------------------------------------------------------------------------------------
	-- Значения скидок разворачиваем
	------------------------------------------------------------------------------------------------------------

	EXEC [dbo].[prc_PRICE_GetLayerSettingsPivot] @Debug = @Debug

	IF(@Debug IN (1,2)) 
	BEGIN
		SELECT 'Скидки'
		SELECT
			*
		FROM
			##DiscountSettingListPivot
		WHERE
			(@PricePolID IS NULL OR PricePolID = @PricePolID) AND
			(@ProductID IS NULL OR ProductID = @ProductID)
		ORDER BY
			PricePolID,ProductID
	END

	DECLARE		
		@InTran			bit


	BEGIN TRY
		IF @@TRANCOUNT > 0 SET @InTran = 1
		ELSE SET @InTran = 0

		IF(@InTran = 0) BEGIN TRANSACTION

		------------------------------------------------------------------------------------------------------------
		--	НДС из справочника продуктов
		------------------------------------------------------------------------------------------------------------
		SELECT
			l.PricePolID,
			l.ProductID, 
			ISNULL(p.NDS,
				CASE (a.[Status]&4) 
					WHEN 4 THEN 18
					WHEN 0 THEN 10
					ELSE 10
				END)
			as NDS,
			ISNULL(p.NDSID,
				CASE (a.[Status]&4) 
					WHEN 4 THEN 18
					WHEN 0 THEN 10
					ELSE 10
				END)
			as NDSID
		INTO
			#NDSProd
		FROM	
			#CalcProductList l
			INNER JOIN	PricePol p WITH(NOLOCK) ON
				p.PricePolID = l.PricePolID
			LEFT JOIN ArhStatusProd a
				ON a.ProdID = l.ProductID
				AND a.[Data] = 
				(
					SELECT 
						MAX([Data]) 
					FROM  
						ArhStatusProd Arh2
					WHERE 	
						Arh2.[Data] <= @CalcDate AND 
						Arh2.ProdID = a.ProdID
				)	
		GROUP BY
			l.PricePolID,
			l.ProductID, 
			p.NDS,
			p.NDSID,
			a.[Status]
			
		IF (@Debug IN (1,2,3))
		BEGIN
			SELECT 'НДС'
			SELECT
				* 
			FROM #NDSProd
			WHERE
				(@ProductID IS NULL OR ProductID = @ProductID)
			ORDER BY
				ProductID
		END

		IF EXISTS(SELECT 1 FROM #NDSProd WHERE NDS IS NULL)
		INSERT INTO #NTLResult(PScore, ErrorMessage)
		SELECT 
			'NTL. Не найдено НДС на продукт:',
			COUNT(*)
		FROM
			#NDSProd nds
		WHERE
			nds.NDS IS NULL	

/*	
		-- выводить список продуктов без НДС
		IF EXISTS(SELECT 1 FROM #NDSProd WHERE NDS IS NULL)
		BEGIN
			INSERT INTO #NTLResult(PScore, ErrorMessage)
			SELECT 
				'NTL. Не найден НДС на продукт:',
				p.PrNomer + ' - ' + p.PrName
			FROM
				#NDSProd nds
				INNER JOIN Products p WITH(NOLOCK) ON
					p.ID = nds.ProductID
			WHERE
				nds.NDS IS NULL	
		END
*/	
		------------------------------------------------------------------------------------------------------------
		--	Актуальные Базовые цены на продукты
		------------------------------------------------------------------------------------------------------------

		-- собираем исключения из аналогов, если они там есть
		;WITH ExBasePriceAnalog AS
		(
			SELECT 
				l.PricePolID,
				l.ProductID,
				ex.BasePrice
			FROM
				#CalcProductList l
				--CROSS APPLY dbo.fnc_GL_GetAnalogProductID(l.ProductID) as exA	
				-- все аналоги продукта для поиска в БЦ искл.
				INNER JOIN Products p WITH(NOLOCK) ON
					p.ID = l.ProductID
				INNER JOIN Products exA WITH(NOLOCK) ON
					p.AGID = exA.AGID
					AND exA.[Status] & 512 = 0			-- не давальческие
				INNER JOIN [dbo].[PLDiscountExceptionSettings] ex ON
					ex.PricePolID = l.PricePolID
					AND ex.ProductID = exA.ID
					AND @CalcDate BETWEEN ex.DateBegin AND ISNULL(ex.DateEnd,65535)
					AND ex.RowState = 1
			GROUP BY
				l.PricePolID,
				l.ProductID,
				ex.BasePrice
		),
		-- Все БЦ по алгоритму
		AllBasePrice AS
		(
			SELECT 
				l.PricePolID,
				l.ProductID,

				-- БЦ выбирается:
				--	1. % скидки из дефолтного слоя, если задан
				--	2. исключение БЦ из настройки исключений
				--	3. БЦ филиала
				CASE
					WHEN g.DiscountPercent IS NOT NULL
						THEN bp.BasePrice*(100 - g.DiscountPercent)/100
					ELSE ISNULL(ex.BasePrice,bpp.BasePrice) 
				END as BasePrice,
				bp.BasePrice as FilialBasePrice,
				g.DiscountPercent
			FROM
				#CalcProductList l
				INNER JOIN PricePol pp WITH(NOLOCK) ON
					pp.PricePolID = l.PricePolID
				-- БЦ филиала, должна быть обязательно
				INNER JOIN le_PLBasePrice bp ON
					bp.ProductID = l.ProductID
					AND bp.BasePriceTypeID = 1							-- БЦ филиала
					AND bp.LegalEntityID = @CurrentLegalEntityID
					AND bp.DatePrice = 
					(
						SELECT 
							MAX(bpa.DatePrice)
						FROM
							le_PLBasePrice bpa
						WHERE
							bpa.LegalEntityID = @CurrentLegalEntityID AND
							bpa.BasePriceTypeID = bp.BasePriceTypeID AND
							bpa.ProductID = bp.ProductID AND
							bpa.DatePrice <= @CalcDate
					)
				-- БЦ типа из прайса
				LEFT JOIN le_PLBasePrice bpp ON
					bpp.ProductID = l.ProductID
					AND bpp.BasePriceTypeID = pp.BasePriceTypeID		-- БЦ типа из прайса
					AND bpp.LegalEntityID = @CurrentLegalEntityID
					AND bpp.DatePrice = 
					(
						SELECT 
							MAX(bppa.DatePrice)
						FROM
							le_PLBasePrice bppa
						WHERE
							bppa.LegalEntityID = @CurrentLegalEntityID AND
							bppa.BasePriceTypeID = bpp.BasePriceTypeID AND
							bppa.ProductID = bpp.ProductID AND
							bppa.DatePrice <= @CalcDate
					)
				-- % в дефолтном слое БЦ
				LEFT JOIN #GroupedPolProductSettings g ON
					g.PricePolID = l.PricePolID
					AND g.ProductID = l.ProductID
					AND g.DiscountPercent <> 0
					AND g.DLayerID = @BPLayerID
				-- исключения по БЦ
				LEFT JOIN ExBasePriceAnalog ex ON	-- все аналоги продукта для поиска в БЦ искл.
					ex.PricePolID = l.PricePolID
					AND ex.ProductID = l.ProductID
		)
		-- убираем одинаковые БЦ
		SELECT 
			PricePolID,
			ProductID,
			BasePrice,
			FilialBasePrice,
			DiscountPercent
		INTO
			#BasePrice
		FROM
			AllBasePrice
		GROUP BY
			PricePolID,
			ProductID,
			BasePrice,
			FilialBasePrice,
			DiscountPercent			


		IF (@Debug IN (1,2,3))
		BEGIN
			SELECT 'БЦ'
			SELECT
				* 
			FROM #BasePrice
			WHERE
				(@ProductID IS NULL OR ProductID = @ProductID)
			ORDER BY
				ProductID
		END

		IF EXISTS(SELECT 1 FROM #BasePrice WHERE BasePrice IS NULL)
		INSERT INTO #NTLResult(PScore, ErrorMessage)
		SELECT 
			'NTL. Не найдено БЦ на продукт:',
			COUNT(*)
		FROM
			#BasePrice bp
		WHERE
			bp.BasePrice IS NULL

/*	
		-- выводить продукты без БЦ
		IF EXISTS(SELECT 1 FROM #BasePrice WHERE BasePrice IS NULL)
		BEGIN
			INSERT INTO #NTLResult(PScore, ErrorMessage)
			SELECT 
				'NTL. Не найдены БЦ на продукт:',
				p.PrNomer + ' - ' + p.PrName
			FROM
				#BasePrice bp
				INNER JOIN Products p WITH(NOLOCK) ON
					p.ID = bp.ProductID
			WHERE
				bp.BasePrice IS NULL
			GROUP BY
				p.PrNomer,p.PrName
		END
*/

		-- продукты по скидкам с рассчетными полями
		SELECT 
			pl.PricePolID as TPricePolID,
			pl.ProductID as TProductID,
			nds.NDS,
			nds.NDSID,
			bp.BasePrice,
			pp.CurrID,
			pp.BasePriceTypeID,
			pp.[Status] as PricePolStatus,
			fv.*,
			f.FixPrice,
			CASE
				WHEN f.ProductID IS NOT NULL THEN 0	-- фикс
				WHEN fv.ProductID IS NULL THEN 1	-- нет значений формулы
				ELSE 0
			END	as IsDiscountEnd,
			pl.IsBlock
		INTO
			#ReadyForCalc
		FROM
			#CalcProductList pl
			LEFT JOIN ##DiscountSettingListPivot fv ON
				pl.PricePolID = fv.PricePolID
				AND pl.ProductID = fv.ProductID
			INNER JOIN PricePol pp ON
				pp.PricePolID = pl.PricePolID
			LEFT JOIN #NDSProd nds ON
				nds.PricePolID = pl.PricePolID
				AND nds.ProductID = pl.ProductID
			LEFT JOIN #BasePrice bp ON
				bp.PricePolID = pl.PricePolID
				AND bp.ProductID = pl.ProductID
			LEFT JOIN #GroupedPolProductFixSettings f ON
				f.PricePolID = pl.PricePolID
				AND f.ProductID = pl.ProductID
		WHERE
			(nds.NDS IS NOT NULL OR pl.IsBlock = 1) AND -- НДС есть или это блокировка продукта
			(bp.BasePrice IS NOT NULL OR pl.IsBlock = 1) -- БЦ есть или это блокировка продукта

		-- нечего считать
		SELECT @IntCount = COUNT(*) FROM #ReadyForCalc

		IF(@Debug IN (1,2,3))
		BEGIN
			SELECT '#ReadyForCalc'
			SELECT 
				*
			FROM
				#ReadyForCalc
			WHERE
				(@PricePolID IS NULL OR TPricePolID = @PricePolID) AND
				(@ProductID IS NULL OR TProductID = @ProductID)
			ORDER BY
				TPricePolID,
				TProductID
		END

		IF(@IntCount = 0)
		BEGIN
			INSERT INTO #NTLResult(PScore, ErrorMessage)
			SELECT 'NTL. Не найдено продуктов для расчёта!',''
--			GOTO TO_END -- цены надо удалить
		END
		------------------------------------------------------------------------------------------------------------
		--	Удалим рассчитанные здесь ранее цены в NewPriceList
		--	И все расчитанные по новому на Дату
		------------------------------------------------------------------------------------------------------------
		DELETE n
		FROM 
			NewPriceList n
			LEFT JOIN #ReadyForCalc c ON
				c.TPricePolID = n.PolType
				AND c.TProductID = n.ProductID			
		WHERE
			(@PricePolID IS NULL OR PolType = @PricePolID) AND
			n.[Data] = @CalcDate AND
			(
				c.TProductID IS NOT NULL OR
				(
					[Status] & 20 = 20 OR --(16 & 4)
					[Status] & 16 = 16 OR
					[Status] & 32 = 32
				)
			)

		DECLARE
			@DSQL nvarchar(MAX),
			@CSName nvarchar(MAX),
			@CName nvarchar(MAX)
		------------------------------------------------------------------------------------------------------------
		-- Смотрим формулу
		-------------------------------------------------------------------------------------
		DECLARE
			@FPart1 varchar(300),
			@FPart2 varchar(300)

		SELECT
			Num,Part,Gr
		INTO 
			#NTLFormulaParts
		FROM
			[dbo].[fnc_PRICE_GetNTLFormulaParts](@CalcDate)

		SELECT 
			@FPart1 = ISNULL(@FPart1,CASE WHEN Num = 2 THEN Part ELSE NULL END),
			@FPart2 = ISNULL(@FPart2,CASE WHEN Num = 3 THEN Part ELSE NULL END)
		FROM
			#NTLFormulaParts

		-- собираем формулу с округлением по частям
		SELECT
			@NTLFormula = Part + '*' + Gr		-- БЦ
		FROM
			#NTLFormulaParts
		WHERE
			Num = 1

		-- формула с промо
		SELECT
			@NTLFormula = @NTLFormula + '*' + Gr
		FROM
			#NTLFormulaParts
		WHERE
			Num = 2	

		-- округление после 2-й группы
		SET @NTLFormula = '
			(CASE
				WHEN ((CurrID > 0) OR ((' + CONVERT(varchar(12), @PrecisionPrice) + ' = 1) AND (PricePolStatus & 256 = 256))) 
					THEN  ROUND(' + @NTLFormula + ', 4) 
				ELSE  ROUND(' + @NTLFormula + ', 2) 
			END)
		'
		-- части после 2-й группы
		SELECT
			@NTLFormula = @NTLFormula + '*' + Gr
		FROM
			#NTLFormulaParts
		WHERE
			Num > 2	

		IF(@Debug BETWEEN 1 AND 9)
			SELECT 'FormulaParts',@FPart1,@FPart2,@NTLFormula

		--GOTO TO_FAIL	-- проверка формулы
		-------------------------------------------------------------------------------------

		-------------------------------------------------------------------------------------
		-- расчет отгрузочных цен
		-------------------------------------------------------------------------------------
		SET
			@DSQL = N'
			INSERT INTO NewPriceList
			(
				ProductID,
				Data,
				PolType,
				Price,
				NDS,
				CurrID,
				[Status],
				BasePriceTypeID,
				NDSID,
				BasePrice,
				Price1,
				Price2
			)
			SELECT 
				TProductID,
				'''+CONVERT(varchar(10),@CalcDate,120)+''' as Data,
				TPricePolID,
				CASE 
					WHEN IsBlock = 1
						THEN 0
					WHEN IsDiscountEnd = 1
						THEN BasePrice
					WHEN FixPrice IS NOT NULL
						THEN FixPrice
					-- округление
					WHEN ((CurrID > 0) OR ((' + CONVERT(varchar(12), @PrecisionPrice) + ' = 1) AND (PricePolStatus & 256 = 256))) 
						THEN  ROUND(' + @NTLFormula + ', 4) 
					ELSE  ROUND(' + @NTLFormula + ', 2) 
				END as Price, 
				NDS,
				CurrID,
				CASE 
					WHEN IsBlock = 1
						THEN 20					-- для блокировки продукта
					WHEN FixPrice IS NOT NULL
						THEN 32					-- Для фикс. цены ставим 32
					ELSE 16						-- Для рассчётных цен ставим 16
				END as [Status],
				BasePriceTypeID,
				NDSID,
				CASE
					WHEN ((CurrID > 0) OR ((' + CONVERT(varchar(12), @PrecisionPrice) + ' = 1) AND (PricePolStatus & 256 = 256))) 
						THEN  ROUND(BasePrice, 4) 
					ELSE  ROUND(BasePrice, 2) 
				END,
				CASE -- Price1 -- После Базовой+Дистр группы
					WHEN (FixPrice IS NOT NULL OR IsDiscountEnd = 1 OR IsBlock = 1)
					THEN 0
					ELSE ('+@FPart1+')
				END,
				CASE  -- Price2 -- После промо группы
					WHEN (FixPrice IS NOT NULL OR IsDiscountEnd = 1 OR IsBlock = 1)
					THEN 0
					ELSE 
						CASE
							WHEN ((CurrID > 0) OR ((' + CONVERT(varchar(12), @PrecisionPrice) + ' = 1) AND (PricePolStatus & 256 = 256))) 
								THEN  ROUND(('+@FPart2+'), 4) 
							ELSE  ROUND(('+@FPart2+'), 2) 
						END
				END
			FROM
				#ReadyForCalc

			INSERT INTO #NTLResult(PScore, ErrorMessage)
			VALUES(''NTL. Найдено новых цен:'',CAST(@@ROWCOUNT as varchar))
		'

		IF(@Debug  BETWEEN 1 AND 9)
			PRINT @DSQL

		EXEC(@DSQL)

		-- 
		IF(@Debug IN (1,2))
		BEGIN
			SELECT 'NewPriceList'
			SELECT 
				*
			FROM
				NewPriceList
			WHERE
				(@PricePolID IS NULL OR PolType = @PricePolID) AND
				[Data] = @CalcDate
		END

		-- проверка отрицательной цены
		IF EXISTS
		(
			SELECT TOP 1 1 			
			FROM
				NewPriceList WITH(NOLOCK)
			WHERE
				Price < 0 AND
				(@PricePolID IS NULL OR PolType = @PricePolID) AND
				[Data] = @CalcDate
		)
		BEGIN
			
			INSERT INTO	#NTLResult
			SELECT 
				'NTL. ОШИБКА', 
				'Продукт № '+p.PrNomer+' по прайс-листу № '+CAST(n.PolType as varchar)+' содержит отрицательную цену!' as ErrorMessage
			FROM
				NewPriceList n WITH(NOLOCK)
				INNER JOIN Products p WITH(NOLOCK) ON
					p.ID = n.ProductID
			WHERE
				n.Price < 0 AND
				(@PricePolID IS NULL OR n.PolType = @PricePolID) AND
				n.[Data] = @CalcDate
		
			SET @ErrorMessage = 'Найдены отрицательные цены!'
			GOTO TO_FAIL
		END

		IF(@MakeChange = 0) GOTO TO_END

		------------------------------------------------------------------------------------------------------------
		--	ОБНОВЛЕНИЕ ТАБЛИЦЫ АРХИВА ЦЕН
		------------------------------------------------------------------------------------------------------------
		
		DECLARE @SummaryOfChanges TABLE(Change VARCHAR(20));  

		-- найдём дату предыдущих цен
		;WITH DatePriceList as
		(
			SELECT
				ProductID,
				Data,
				PolType,
				Price,
				NDS,
				CurrID,
				[Status],
				BasePriceTypeID,
				NDSID,
				BasePrice,
				Price1,
				Price2
			FROM
				ArhPriceList 
			WHERE
				Data = @CalcDate AND
				(@PricePolID IS NULL OR PolType = @PricePolID) 
		)
		MERGE 
			DatePriceList as a
		USING 
		(
			SELECT
				nn.ProductID,
				nn.Data,
				nn.PolType,
				nn.Price,
				nn.NDS,
				nn.CurrID,
				nn.[Status],
				nn.BasePriceTypeID,
				nn.NDSID,
				nn.BasePrice,
				nn.Price1,
				nn.Price2
/*
				CASE
					WHEN ll.ProductID IS NOT NULL
						THEN 1
					ELSE 0
				END as IsSamePrice							-- расчитанная цена равна предыдущей из архива ?
*/
			FROM				
				NewPriceList nn	
				--LEFT JOIN LastSameArhPrice ll ON
				--	nn.PolType = ll.PolType AND
				--	nn.ProductID = ll.ProductID 	
			WHERE
				(@PricePolID IS NULL OR nn.PolType = @PricePolID) AND
				(
					nn.[Status] & 20 = 20 OR --(16 & 4)
					nn.[Status] & 16 = 16 OR
					nn.[Status] & 32 = 32
				) AND
				nn.Data = @CalcDate
		) as n
		ON
		(
			a.PolType = n.PolType AND
			(@PricePolID IS NULL OR a.PolType = @PricePolID) AND
			a.ProductID = n.ProductID AND
			a.Data  = n.Data 
		)
		WHEN NOT MATCHED BY SOURCE AND						--	когда есть запись на дату, а в расчете её нет 
			a.Data = @CalcDate AND
			(@PricePolID IS NULL OR a.PolType = @PricePolID) AND --	расчет по прайсу или по всем
			(
				a.[Status] & 20 = 20 OR --(16 & 4)
				a.[Status] & 16 = 16 OR
				a.[Status] & 32 = 32
			)
			THEN DELETE
		--WHEN MATCHED AND  IsSamePrice = 1
		--	THEN DELETE										--	когда в архиве есть, но такаяже есть и раньше
		WHEN MATCHED AND									--	когда есть запись на дату в архиве и расчете, но цены не совпадают
			(
				a.Price <> n.Price OR
				a.NDSID <> n.NDSID OR
				a.[Status] <> n.[Status]
			)
			THEN UPDATE
			SET
				a.Price = n.Price,
				a.NDS = n.NDS,
				a.CurrID = n.CurrID,
				a.[Status] = n.[Status],
				a.BasePriceTypeID = n.BasePriceTypeID,
				a.NDSID = n.NDSID,
				a.BasePrice = n.BasePrice,
				a.Price1 = n.Price1,
				a.Price2 = n.Price2
		WHEN NOT MATCHED BY TARGET THEN -- когда нет в архиве записи на дату --( AND IsSamePrice = 0 и предыдущая цена не такая же)
		INSERT
		(
			ProductID,
			Data,
			PolType,
			Price,
			NDS,
			CurrID,
			[Status],
			BasePriceTypeID,
			NDSID,
			BasePrice,
			Price1,
			Price2
		)
		VALUES
		(
			ProductID,
			Data,
			PolType,
			Price,
			NDS,
			CurrID,
			[Status],
			BasePriceTypeID,
			NDSID,
			BasePrice,
			Price1,
			Price2
		)
		OUTPUT $action INTO @SummaryOfChanges;  

		IF (@@ERROR <> 0) 
		BEGIN
			SET @ErrorMessage = ERROR_MESSAGE()

			GOTO TO_FAIL
		END

		INSERT INTO #NTLResult(PScore, ErrorMessage) 
		SELECT 
			'NTL. Обновление архива цен',
			CASE Change
				WHEN 'INSERT' THEN 'Добавлено цен: ' + CAST(COUNT(*) as varchar(10))
				WHEN 'UPDATE' THEN 'Обновлено цен: ' + CAST(COUNT(*) as varchar(10))
				WHEN 'DELETE' THEN 'Удалено   цен: ' + CAST(COUNT(*) as varchar(10))
			END
		FROM @SummaryOfChanges  
		GROUP BY Change;

		IF NOT EXISTS (SELECT TOP 1 1 FROM @SummaryOfChanges)
		INSERT INTO #NTLResult(PScore, ErrorMessage) 
		VALUES('NTL. Обновление архива цен','Цены не изменились!')		

		-- рассчитаем слои для цен
		EXEC @Ret = [dbo].[prc_PRICE_MakeArhPriceLayers] @CalcDate=@CalcDate,@Debug=@Debug,@PricePolID=@PricePolID

		IF (@Ret <> 0 OR @@ERROR <> 0) 
		BEGIN
			SET @ErrorMessage = ERROR_MESSAGE()

			GOTO TO_FAIL
		END

		IF(@InTran = 0 AND @@TRANCOUNT > 0) COMMIT TRAN

		GOTO TO_END
	END TRY
	BEGIN CATCH		
		IF(@Debug  BETWEEN 1 AND 10) PRINT 'In Catch'

		IF(@ErrorMessage IS NULL) 
			SET @ErrorMessage = ERROR_MESSAGE()

		-- Save results
		IF (OBJECT_ID('tempdb..#NTLResult') IS NOT NULL) 
			INSERT INTO	@NTLResult
			SELECT PScore, ErrorMessage FROM #NTLResult ORDER BY ID

		IF(@InTran = 0 AND @@TRANCOUNT > 0) ROLLBACK TRAN
	
		-- load results back
		IF EXISTS(SELECT 1 FROM @NTLResult) AND (OBJECT_ID('tempdb..#NTLResult') IS NOT NULL) 
		BEGIN
			TRUNCATE TABLE #NTLResult

			INSERT INTO	#NTLResult
			SELECT PScore, ErrorMessage FROM @NTLResult ORDER BY ID
		END

		GOTO TO_FAIL
	END CATCH

--*/

TO_FAIL:
	SET @Ret = 50001

	-- Save results
	IF (OBJECT_ID('tempdb..#NTLResult') IS NOT NULL) 
	BEGIN
		DELETE FROM @NTLResult

		INSERT INTO	@NTLResult
		SELECT PScore, ErrorMessage FROM #NTLResult ORDER BY ID
	END

	IF(@InTran = 0 AND @@TRANCOUNT > 0) ROLLBACK TRAN

	-- load results back
	IF EXISTS(SELECT 1 FROM @NTLResult) AND (OBJECT_ID('tempdb..#NTLResult') IS NOT NULL) 
	BEGIN
		TRUNCATE TABLE #NTLResult

		INSERT INTO	#NTLResult
		SELECT PScore, ErrorMessage FROM @NTLResult ORDER BY ID
	END

	INSERT INTO #NTLResult
	SELECT 'NTL. ОШИБКА',@ErrorMessage

	INSERT INTO #NTLResult
	SELECT 'NTL. ОШИБКА','РАСЧЁТ ОТМЕНЁН!'


TO_END:

	IF(@InTran = 0 AND @@TRANCOUNT > 0) COMMIT TRAN

	IF(@Debug  BETWEEN 1 AND 10) AND (OBJECT_ID('tempdb..#NTLResult') IS NOT NULL) 
		SELECT * FROM #NTLResult
/*
	SET @EndTime = GETDATE()   

	SELECT
		@TotalTimeStr = 
			CAST((DATEDIFF(ss,@StartTime,@EndTime)/60/60%60) as varchar(10))+' час, '+
			CAST((DATEDIFF(ss,@StartTime,@EndTime)/60%60) as varchar(10))+' мин, '+
			CAST(DATEDIFF(ss,@StartTime,@EndTime)%60 as varchar(10))+' сек'
	 
	INSERT INTO #NTLResult(PScore, ErrorMessage)
	VALUES ('Процедура', 'Время выполнения: '+@TotalTimeStr)
*/	
DELETE_TEMP:
	IF (OBJECT_ID('tempdb..##prc_PRICE_MakeArhPriceListNTL') IS NOT NULL) 
		DROP TABLE ##prc_PRICE_MakeArhPriceListNTL
	IF (OBJECT_ID('tempdb..##DiscountSettingListPivot') IS NOT NULL) 
		DROP TABLE ##DiscountSettingListPivot

	RETURN @Ret
END
GO


