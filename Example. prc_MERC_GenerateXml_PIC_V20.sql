CREATE PROCEDURE [dbo].[prc_MERC_GenerateXml_PIC_V20]
	@LocalTransactionID bigint,					-- Идентификатор заявки в клиентской системе, ИД ЖОМ
	@DocID int = NULL,							-- ИД деталировки первичного документа
	@DocTypeID int = NULL,						-- Тип документа EksDetNakl или межфилиалка
	@VetDocument_UUID uniqueidentifier = NULL,	-- uuid ВСД или ТВСД для автоматического гашения
	@OutMessage xml = NULL OUTPUT,				-- Формируемое сообщение
	@ErrorMessage  nvarchar(255) = NULL OUTPUT,	-- Сообшение об ошибке
	@Debug bit	= 0								-- Флаг отладки процедуры
AS
/*
  Procedure - part of Mercury project started on Russia in 2017 year.
  Just example of XML modifying process (XML DML)

	Описание:
		Интерфейс № 3
		Создание интерфейсного сообщения по передаче из Лиасофт в Меркурий на гашение ТВСД
		Вызывается из:
			Подтверждение межфилиалки					сценарии:	1111, 1121 (<), 1131 (0) , 1211 (>)
			Подтверждение возврата						сценарии:	1112
			Автоматическое гашение Возвратных ВСД		сценарии:	1113
			Автоматическое гашение Транспортных ВСД		сценарий:	1114

	Формат входящего сообщения:		http://help.vetrf.ru/wiki/GetVetDocumentByUuidOperation_v2.0
	Формат формируемого сообщения:	http://help.vetrf.ru/wiki/ProcessIncomingConsignment_v2.0

	Параметры:
		@DocID		- ИД деталировки первичного документа
		@DocTypeID	- Тип документа EksDetNakl или межфилиалка
		@VetUUID	- uuid ВСД или ТВСД

	Запуск:
		---------------------------------------------------------------------------------------
		-- Автоматика - Автоматическое гашение Возвратных и Транспортных ВСД
		---------------------------------------------------------------------------------------

		DECLARE
			@OutMessage xml,
			@ErrorMessage  nvarchar(255)
		EXEC prc_MERC_GenerateXml_PIC_V20 
			@LocalTransactionID = 274,
			@VetDocument_UUID = '1B5CDCB6-EC62-40E6-B205-F975E9599C17', 
			@OutMessage = @OutMessage OUTPUT, 
			@ErrorMessage  = @ErrorMessage  OUTPUT, 
			@Debug = 1

		SELECT @OutMessage as OutMessage, @ErrorMessage  as ErrorMsg

		---------------------------------------------------------------------------------------
		-- Первичка - возвраты и межфилиалка
		---------------------------------------------------------------------------------------

		DECLARE
			@OutMessage xml,
			@ErrorMessage  nvarchar(255)
		EXEC prc_MERC_GenerateXml_PIC_V20 
			@LocalTransactionID = 777,
			@DocID = -1, 
			@DocTypeID = -1,
			@VetDocument_UUID = '8B05F0D0-04A1-4873-A2AB-ADE92D9A4565',
			@OutMessage = @OutMessage OUTPUT, 
			@ErrorMessage  = @ErrorMessage  OUTPUT, 
			@Debug = 1

		SELECT @OutMessage as OutMessage, @ErrorMessage  as ErrorMsg

		---------------------------------------------------------------------------------------

		SELECT TOP 100
		*
		FROM
			MercuryVetDocument
		WHERE 
			MVDID = 13

		exec prc_MERC_MercuryQueueProcess
		update MercuryRequestQueue SET Status = 11 WHERE MRQID = 30

		SELECT TOP 100
		*
		FROM
			 MercuryRequestQueue

		SELECT TOP 100
		*
		FROM
			MercuryStockEntry

	Изменения:
		2018.03.28, Некрасов П.А., C254679, создал и назвал. 
		2018.04.12, Мамонов А.В. Создана основа и дописана
*/
BEGIN

	SET NOCOUNT ON;

	DECLARE
		@BaseTableID int,
		@ScriptType int,							-- Сценарий формирования, определяется, от него зависит формат формируемого сообщения
	
		-- Из первички
		@DocDate smalldatetime,						-- дата приходного документа
		@deliveryDate smalldatetime,				-- Дата оформления входящей партии. fnc_EDI_FormatDateToStr
		@volume decimal(22,6),						-- Объем продукции, которую приняли
		@returnedVolume decimal(22,6),				-- Объем продукции, которую НЕ приняли 
		@vetDocument xml,							-- вет.документ
		@Batch_BatchID	nvarchar(510),				-- № КУ из сообщения
		@NumberKU	int								-- № КУ из нашей первички

-- Алгоритм
/*
	@ScriptType - Сценарии формирования сообщения
	1.1.1 - Сведения во входящем ВСД соответствуют фактическим, партия принимается в полном объеме
		1111 - приход по факту без расхождений при межфилиалке;
		1112 - приход при возвратах;
		1113 - автоматическое гашение возвратных ВСД;
		1114 - автоматическое гашение ТВСД по излишкам при МФ перемещении из OEBS в Лиасофт.
		Особености:  
			1. Входящий ВСД переходит в статус "погашен";
			2. В складском журнале продукции и хранилище стока Меркурия появляется новая запись, которая содержит сведения о поступившей продукции
		Данные полей:
			deliveryFacts/docInspection/result 	CORRESPONDS 	Данные о грузе соответствуют указанным в ВСД. 
			deliveryFacts/vetInspection/result 	UNSUPERVISED 	Сведения о результате ветеринарного осмотра партии продукции. 
			deliveryFacts/decision 				ACCEPT_ALL 		Партия принимается полностью. 
			discrepancyReport 					Не заполняется 	Расхождений сведений указанных в ВСД с фактическими нет, акта для этого сценария не требуется. 
			returnedDelivery 					Не заполняется 	Возврат продукции не оформляется, сведения о возвратном сертификате не требуются. 

	1.1.2 - Сведения во входящем ВСД соответствуют фактическим, партия принимается частично, на часть объема оформляется возврат
		1121 - приход по факту меньшего количества при межфилиалке
		Особености:  
			1. Входящий ВСД переходит в статус "погашен".
			2. В складском журнале продукции появляется новая запись, которая содержит сведения о поступившей продукции с тем объемом, который был указан в поле delivery/consignment/volume. 
			3. Оформлен возвратный ВСД. В возвратном ВСД объем указывается в поле returnedDelivery/consignment/volume. 5%.
		Данные полей:
			deliveryFacts/docInspection/result 	CORRESPONDS 				Данные о грузе соответствуют указанным в ВСД. 
			deliveryFacts/vetInspection/result 	UNSUPERVISED 				Сведения о результате ветеринарного осмотра партии продукции. 
			deliveryFacts/decision 				PARTIALLY 					Партия принимается частично. На часть партии оформляется возврат. 
			discrepancyReport 					Не заполняется 				Расхождений сведений указанных в ВСД с фактическими нет, акта для этого сценария не требуется. 
			returnedDelivery 					Оформляется возвратный ВСД 	Объем возвращаемой партии плюс объем принимаемой партии должен быть равен объему партии, 5%.

	1.1.3 - Сведения во входящем ВСД соответствуют фактическим, партия не принимается, на весь объем входящей партии оформляется возврат
		1131 - приход по факту 0 при межфилиалке.
		Особености:  
			1.	Входящий ВСД переходит в статус "погашен".
			2.	Оформлен возвратный ВСД. В возвратном ВСД установлен объем, равный объему партии, 5%.
		Данные полей:
			deliveryFacts/docInspection/result 	CORRESPONDS 				Данные о грузе соответствуют указанным в ВСД. 
			deliveryFacts/vetInspection/result 	UNSUPERVISED 				Сведения о результате ветеринарного осмотра партии продукции. 
			deliveryFacts/decision 				RETURN_ALL 					На всю партию оформляется возврат. 
			discrepancyReport 					Не заполняется 				Расхождений сведений указанных в ВСД с фактическими нет, акта для этого сценария не требуется. 
			returnedDelivery 					Объём возвращаемой партии. 	В данном случае объем возвращаемой партии должен быть равен объему партии, 5%

	1.2.1 - Сведения во входящем ВСД не соответствуют фактическим, партия принимается в полном объеме
		1211 - приход по факту излишков при межфилиалке.
		Особености:
			1.	Входящий ВСД переходит в статус "погашен".
			2.	В складском журнале продукции появляется новая запись, которая содержит фактические сведения о поступившей продукции.
			3.	Создан акт несоответствия, в котором фиксируются расхождения и указывается причина несоответствия.
		Данные полей:
			deliveryFacts/docInspection/result 	MISMATCH 		Данные о грузе не соответствуют указанным в ВСД. 
			deliveryFacts/vetInspection/result 	UNSUPERVISED 	Сведения о результате ветеринарного осмотра партии продукции. 
			deliveryFacts/decision				ACCEPT_ALL 		Партия принимается полностью. 
			discrepancyReport 	Указывается причина несоответствия и опционально серия/номер/дата бумажного акта, если таковой составляется 	Данная причина будет указана в составленном акте несоответствия, акт составляется автоматически, если в объекте с фактическими сведениями передается информация отличная от указанной в ветеринарном сертификате. 
			returnedDelivery 					Не заполняется 	Возврат продукции не оформляется, сведения о возвратном сертификате не требуются. 

	1.2.2 - Сведения во входящем ВСД не соответствуют фактическим, партия принимается частично, на часть объема оформляется возврат
		Не реализуется
	1.2.3 - Сведения во входящем ВСД не соответствуют фактическим, партия не принимается, на весь объем входящей партии оформляется возврат
		Не реализуется
*/

/*
	volume
	фактическое количество из документа, пересчитанное в кг по формуле: количество продукта * фасовка * вес нетто
	количество продукта – из деталировки прихода из поля «количество продукта»;
	фасовка – из деталировки прихода из поля «фасовка продукта»;
	вес нетто – из централизованного справочника «ГСП» из поля «Точный вес»
	Значение может иметь 6 знаков после запятой"
*/
	SET @Debug = ISNULL(@Debug,0)

	-- Замена 0 на NULL
	SET @DocID = CASE WHEN @DocID = 0 THEN NULL ELSE @DocID END
	SET @DocTypeID = CASE WHEN @DocTypeID = 0 THEN NULL ELSE @DocTypeID END
	
	IF(
		(@LocalTransactionID IS NULL) OR
		(@VetDocument_UUID IS NULL)	
	)
	BEGIN
		SET @ErrorMessage  = 'Ошибка в prc_MERC_GenerateXml_PIC_V20: не правильно заданы входные парамеры вызова!'
		RETURN 50001
	END

	BEGIN TRY

		IF @DocID IS NOT NULL AND @DocTypeID IS NOT NULL
		BEGIN
			SELECT 
				@BaseTableID = BaseTableID
			FROM
				DocTypes d WITH(NOLOCK)
			WHERE
				DocTypID = @DocTypeID

			IF(@@ROWCOUNT = 0)
			BEGIN
				SET @ErrorMessage  = CONCAT('Ошибка в prc_MERC_GenerateXml_PIC_V20: Не найден тип документов @DocTypeID = ', ISNULL(@DocTypeID,0))
				RETURN 50001
			END

			IF(@BaseTableID = 26)		-- EksDetVozvr Возврат
			BEGIN
				SELECT 
					@ScriptType = 1112,
	--				@volume = det.CountProd * p.PrSubNomer * cp.PreciseWeight,
					@DocDate = doc.[Data],
					@deliveryDate = doc.[Data],
					@vetDocument = mvd.RawData,
					@NumberKU = mvd.NumberKU,
					@Batch_BatchID = mvd.Batch_BatchID
				FROM
					EksDetVozvr det WITH(NOLOCK)
					INNER JOIN EksDocVozvr doc WITH(NOLOCK) ON
						doc.ID = det.EksDocumID
					INNER JOIN Products p WITH(NOLOCK) ON
						p.ID = det.ProductID
					INNER JOIN c_Products cp WITH(NOLOCK) ON
						cp.ProductID = p.ProdID
					LEFT JOIN MercuryVetDocument mvd WITH(NOLOCK) ON
						mvd.UUID = det.VetDocument_UUID
				WHERE
					det.ID = @DocID		

				IF(@@ROWCOUNT = 0)
				BEGIN
					SET @ErrorMessage  = CONCAT('Ошибка в prc_MERC_GenerateXml_PIC_V20: Не найден ИД деталировки возврата EksDetVozvr.ID = ', ISNULL(@DocID,0))
					RETURN 50001
				END

				IF(@vetDocument IS NULL)
				BEGIN
					SET @ErrorMessage  = CONCAT('Ошибка в prc_MERC_GenerateXml_PIC_V20: Не найден веи документ в строке деталировки возврата EksDetVozvr.ID = ', ISNULL(@DocID,0))
					RETURN 50001
				END
			END
			ELSE IF(@BaseTableID = 2)	-- TTNNAP Межфилиалка
			BEGIN
				SELECT
					@ScriptType =	CASE 
										-- приход по факту меньшего количества при межфилиалке
										WHEN det.KolProdFact < det.KolProd THEN 1121 
										-- приход по факту излишков при межфилиалке.
										WHEN det.KolProdFact > det.KolProd THEN 1211
										-- приход по факту без расхождений при межфилиалке: KolProd = KolProdFact
										ELSE 1111	
									END,
					@volume = det.KolProdFact * p.PrSubNomer * cp.PreciseWeight,
					@returnedVolume = CASE WHEN (det.KolProd > det.KolProdFact) THEN det.KolProd - det.KolProdFact ELSE 0 END *
										p.PrSubNomer * cp.PreciseWeight,
					@DocDate = doc.[Data],
					@deliveryDate  = doc.[Data],
					@NumberKU = mvd.NumberKU,
					@Batch_BatchID = mvd.Batch_BatchID,
					@vetDocument = mvd.RawData
				FROM
					TTNNAP det WITH(NOLOCK)
					INNER JOIN TTN doc WITH(NOLOCK) ON
						doc.ID = det.TTNID
					INNER JOIN Products p WITH(NOLOCK) ON
						p.ID = det.ProductID
					INNER JOIN c_Products cp WITH(NOLOCK) ON
						cp.ProductID = p.ProdID
					LEFT JOIN MercuryVetDocument mvd WITH(NOLOCK) ON
						mvd.UUID = det.VetDocument_UUID
				WHERE
					det.ID = @DocID
	
				-- Алгоритм обновление кол-ва в сообщении
				--	1121 - приход по факту меньшего количества при межфилиалке
				--	1131 - приход по факту 0 при межфилиалке
				--	1211 - приход по факту излишков при межфилиалке
				IF(@ScriptType NOT IN (1121,1131,1211))
					SET @volume = NULL	--	не обновлять

				IF(@@ROWCOUNT = 0)
				BEGIN
					SET @ErrorMessage  = CONCAT('Ошибка в prc_MERC_GenerateXml_PIC_V20: Не найден ИД деталировки межфилиалки TTNNAP.ID = ', ISNULL(@DocID,0))
					RETURN 50001
				END

				IF(@vetDocument is NULL)
				BEGIN
					SET @ErrorMessage  = CONCAT('Ошибка в prc_MERC_GenerateXml_PIC_V20: Не найден веи документ в строке деталировки межфилиалки TTNNAP.ID = ', ISNULL(@DocID,0))
					RETURN 50001
				END
			END
			ELSE 
			BEGIN
				SET @ErrorMessage  = CONCAT('Ошибка в prc_MERC_GenerateXml_PIC_V20: @BaseTableID = ',ISNULL(@BaseTableID,0),' не используется!')
				RETURN 50001
			END
		END
		ELSE
		IF @VetDocument_UUID IS NOT NULL
		BEGIN
			-- Автоматика - гашение ВВСД и ТВСД
			SELECT
				@ScriptType =	CASE mvd.VetDType
									WHEN 'TRANSPORT' THEN 1114	-- 1114 - автоматическое гашение ТВСД по излишкам при МФ перемещении из OEBS в Лиасофт.
									WHEN 'RETURNABLE' THEN 1113	-- 1113 - автоматическое гашение возвратных ВСД;
									ELSE 0	-- фигня
								END,							
				@vetDocument = mvd.RawData,
				@DocDate = GETDATE(),
				@deliveryDate = GETDATE(),
				@NumberKU = mvd.NumberKU,
				@Batch_BatchID = mvd.Batch_BatchID
			FROM
				MercuryVetDocument mvd WITH(NOLOCK)
			WHERE
				UUID = @VetDocument_UUID

			IF(@@ROWCOUNT = 0)
			BEGIN
				SET @ErrorMessage  = CONCAT('Ошибка в prc_MERC_GenerateXml_PIC_V20: @VetDocument_UUID = ',@VetDocument_UUID,' не найден в таблице вет. сертификатов!')
				RETURN 50001
			END
		END
		ELSE
		BEGIN
			SET @ErrorMessage  = 'Ошибка в prc_MERC_GenerateXml_PIC_V20: не правильно заданы входные парамеры вызова!'
			RETURN 50001
		END

		IF ISNULL(@ScriptType,0) = 0
		BEGIN
			SET @ErrorMessage  = 'Ошибка в prc_MERC_GenerateXml_PIC_V20: не определился сценарий формирования сообщения!'
			RETURN 50001
		END

		DECLARE		
			@Message xml,
			@ErrMsg	nvarchar(225),
			@issuerId uniqueidentifier,
			@Login varchar(20),
			@delivery xml,
			@deliveryFacts xml,
			@docInspectionResult varchar(50),
			@vetInspectionResult varchar(50),		
			@decision varchar(50),						-- Принятое решение о приёме входной партии.
			@HasDiscrepancyReport bit,					-- Надо ли заполнять discrepancyReport
			@HasReturnedDelivery bit,					-- Надо ли заполнять returnedDelivery
			@UpdateNumberKU bit,						-- Надо ли обновлять № КУ в сообщении на наш

			-- Для формирования XML
			@consignment xml,
			@consignee xml,
			@consignor xml,
			@broker xml,
			@transportInfo xml,
			@transportStorageType xml,
			@shipmentRoute xml,
			@accompanyingForms xml,
			@discrepancyReport xml,
			@returnedDelivery xml
	
		-- Заполнение полей согласно описанному выше алгоритму
		SELECT
			@docInspectionResult	=	CASE WHEN @ScriptType IN (1111,1112,1113,1114,1121,1131) THEN 'CORRESPONDS'
											 WHEN @ScriptType IN (1211) THEN 'MISMATCH'
										END,
			@vetInspectionResult	=	'UNSUPERVISED',
			@decision				=	CASE WHEN @ScriptType IN (1111,1112,1113,1114,1211) THEN 'ACCEPT_ALL'
											 WHEN @ScriptType IN (1121) THEN 'PARTIALLY'
											 WHEN @ScriptType IN (1131) THEN 'ACCEPT_ALL'
										END,
			@HasDiscrepancyReport	=	CASE WHEN @ScriptType IN (1211) THEN 1
											 ELSE 0
										END,
			@HasReturnedDelivery	=	CASE WHEN @ScriptType IN (1121, 1131) THEN 1
											 ELSE 0
										END,
			@UpdateNumberKU			=	0


		-- сравнить КУ, если не равны , то @HasDiscrepancyReport = 1, @docInspectionResult='MISMATCH'
		-- Обновлять № КУ наш в сообщении
		IF(CAST(@NumberKU as nvarchar(510)) <> @Batch_BatchID)
		BEGIN
			SELECT
				@HasDiscrepancyReport = 1,
				@docInspectionResult = 'MISMATCH',
				@NumberKU = ISNULL(@NumberKU,0),
				@UpdateNumberKU = 1
		END
	
		SELECT
			-- Из справочника НСИ – Финансово-аналитические – СПГВБД - «Предприятия группы» из поля «GUID» по головному предприятию
			@issuerId = MercuryBusinessEntityGUID,
			-- Из справочника НСИ – Финансово-аналитические – СПГВБД - «Предприятия группы» из поля «Логин администратора площадки в Меркурии» по филиалу-отправителю сообщения
			@Login = MercuryLoginName
		FROM
			c_HoldingLegalEntities WITH (NOLOCK)
		WHERE
			LegalEntityID = dbo.Cfg_GetCurrentFirmID()

		IF(@Debug = 1)
			SELECT 
				@issuerId as issuerId, @Login as [Login], @deliveryDate as deliveryDate

		-- шаблон формируемого сообщения
		;WITH XMLNAMESPACES (
			'urn:pepsico:ru:mercury:2.0:DT:MercuryG2BApplications' AS merc,	--n1
			'urn:pepsico:ru:mercury:2.0:DT:VetDocument' AS vetd,			--n2
			'urn:pepsico:ru:mercury:2.0:Service:ERPOut' AS ws)				--n0
		SELECT @Message =(
			SELECT
				--Идентификатор заявки в клиентской системе
				@LocalTransactionID AS [ws:localTransactionId],
				--GUID по головному предприятию
				LOWER(CAST(@issuerId AS varchar(36))) AS [ws:issuerId],
				--дата и время формирования сообщения
				GETDATE() AS [ws:issueDate],
				--Логин пользователя, зарегистрированного в системе Меркурий
				@Login AS [ws:data/merc:initiator/vetd:login],
				'' as [ws:data/merc:delivery],
				@deliveryDate as [ws:data/merc:delivery/vetd:deliveryDate]			-- Указывается дата поступления груза. 
		FOR XML PATH('ws:MT_RU_IncomingConsignmentRequest'), TYPE)

		;WITH XMLNAMESPACES
		(
				'urn:pepsico:ru:mercury:2.0:DT:VetDocument' as vetd,
				'urn:pepsico:ru:mercury:2.0:DT:MercuryG2BApplications' AS merc
		)
		SELECT
			-- Фактические сведения о принимаемой партии продукции 
			@consignor = @vetDocument.query('//vetd:vetDocument/vetd:certifiedConsignment/vetd:consignor'),
			-- Сведения о получателе продукции
			@consignee = @vetDocument.query('//vetd:vetDocument/vetd:certifiedConsignment/vetd:consignee'),
			-- Сведения о принимаемой партии продукции или группе животных.
			@consignment = 
			(
				SELECT
					@vetDocument.query('//vetd:vetDocument/vetd:certifiedConsignment/vetd:batch/*')
				FOR XML PATH('vetd:consignment'), TYPE
			),
			-- Фирма-посредник (перевозчик продукции)
			@broker = @vetDocument.query('//vetd:vetDocument/vetd:certifiedConsignment/vetd:broker'),
			-- Информация о транспорте. Не указывается в случае, если происходит смена владельца без перевозки
			@transportInfo = @vetDocument.query('//vetd:vetDocument/vetd:certifiedConsignment/vetd:transportInfo'),
			-- Способ хранения продукции при перевозке.
			@transportStorageType = @vetDocument.query('//vetd:vetDocument/vetd:certifiedConsignment/vetd:transportStorageType'),
			-- Сведения о маршруте следования (пунктах перегрузки).
			@shipmentRoute = @vetDocument.query('//vetd:vetDocument/vetd:certifiedConsignment/vetd:shipmentRoute'),
			-- Дополнительные сведения, необходимые для оформления ветеринарно-сопроводительного документа
			@accompanyingForms = 
			(
				SELECT
					@vetDocument.query('//vetd:vetDocument/vetd:referencedDocument/vetd:issueNumber') as [vetd:waybill],
					@vetDocument.query('//vetd:vetDocument/vetd:referencedDocument/vetd:issueDate') as [vetd:waybill],
					@vetDocument.query('//vetd:vetDocument/vetd:referencedDocument/vetd:type') as [vetd:waybill],
					@vetDocument.query('//vetd:vetDocument/vetd:certifiedConsignment/vetd:transportInfo') as [vetd:waybill],
					@vetDocument.query('//vetd:vetDocument/vetd:uuid') as [vetd:vetCertificate]
				FOR XML PATH('vetd:accompanyingForms'), TYPE
			),
			-- Результаты приёмки
			@deliveryFacts =
			(
				SELECT
					--Природа ВСД (электронный или бумажный)
					'ELECTRONIC' AS [vetd:vetCertificatePresence],
					--Логин пользователя, зарегистрированного в системе Меркурий
					@Login AS [vetd:docInspection/vetd:responsible/vetd:login],
					--Результат соответствия
					@docInspectionResult AS [vetd:docInspection/vetd:result],
					@Login AS [vetd:vetInspection/vetd:responsible/vetd:login],
					@vetInspectionResult AS [vetd:vetInspection/vetd:result],
					@decision AS [vetd:decision]
				FOR XML PATH('merc:deliveryFacts'), TYPE
			),
			-- Акт о несоответствии
			@discrepancyReport = 
			(
				SELECT	
					-- Серия акта несоответствия. Для электронного акта несоответствия серия генерируется автоматически.
					'' as [vetd:issueSeries], -- WE
					-- Номер акта несоответствия. Для электронного акта несоответствия номер генерируется автоматически. номер приходного документа
					@DocID as [vetd:issueNumber],
					-- дата приходного документа
					CAST(@DocDate as date)  as [vetd:issueDate],
					-- Причина составления акта несоответствия.	константа
					'Ошибка поставщика' as [vetd:reason/vetd:name],
					-- Описание несоответствия.
					'' as [vetd:description]
				FOR XML PATH('merc:discrepancyReport'), TYPE
			),
			-- ШАБЛОН. Сведения о возвращаемой партии (возвратном ВСД).
			@returnedDelivery = 
				(
					SELECT
						''
					FOR XML PATH('merc:returnedDelivery'), TYPE
				)
			
		-- Заполняем шаблон @Message кусками
		--consignor
		SET @Message.modify('
			declare namespace ws="urn:pepsico:ru:mercury:2.0:Service:ERPOut";
			declare namespace merc="urn:pepsico:ru:mercury:2.0:DT:MercuryG2BApplications";
			insert sql:variable("@consignor") as last into (/ws:MT_RU_IncomingConsignmentRequest/ws:data/merc:delivery)[1]')

		--consignee
		SET @Message.modify('
			declare namespace ws="urn:pepsico:ru:mercury:2.0:Service:ERPOut";
			declare namespace merc="urn:pepsico:ru:mercury:2.0:DT:MercuryG2BApplications";
			insert sql:variable("@consignee") as last into (/ws:MT_RU_IncomingConsignmentRequest/ws:data/merc:delivery)[1]')

		--consignment data from batch
		SET @Message.modify('
			declare namespace ws="urn:pepsico:ru:mercury:2.0:Service:ERPOut";
			declare namespace merc="urn:pepsico:ru:mercury:2.0:DT:MercuryG2BApplications";
			insert sql:variable("@consignment") as last into (/ws:MT_RU_IncomingConsignmentRequest/ws:data/merc:delivery)[1]')

		--broker
		SET @Message.modify('
			declare namespace ws="urn:pepsico:ru:mercury:2.0:Service:ERPOut";
			declare namespace merc="urn:pepsico:ru:mercury:2.0:DT:MercuryG2BApplications";
			insert sql:variable("@broker") as last into (/ws:MT_RU_IncomingConsignmentRequest/ws:data/merc:delivery)[1]')

		-- update batchID
		IF(@UpdateNumberKU = 1)
			SET @Message.modify('
				declare namespace ws="urn:pepsico:ru:mercury:2.0:Service:ERPOut";
				declare namespace merc="urn:pepsico:ru:mercury:2.0:DT:MercuryG2BApplications";
				declare namespace vetd="urn:pepsico:ru:mercury:2.0:DT:VetDocument";
				replace value of 
					 (/ws:MT_RU_IncomingConsignmentRequest/ws:data/merc:delivery/vetd:consignment/vetd:batchID/text())[1] 
				with sql:variable("@NumberKU")')

		-- update volume
		IF(@volume IS NOT NULL)
			SET @Message.modify('
				declare namespace ws="urn:pepsico:ru:mercury:2.0:Service:ERPOut";
				declare namespace merc="urn:pepsico:ru:mercury:2.0:DT:MercuryG2BApplications";
				declare namespace vetd="urn:pepsico:ru:mercury:2.0:DT:VetDocument";
				replace value of 
					 (/ws:MT_RU_IncomingConsignmentRequest/ws:data/merc:delivery/vetd:consignment/vetd:volume/text())[1] 
				with sql:variable("@volume")')

		--@transportInfo
		SET @Message.modify('
			declare namespace ws="urn:pepsico:ru:mercury:2.0:Service:ERPOut";
			declare namespace merc="urn:pepsico:ru:mercury:2.0:DT:MercuryG2BApplications";
			insert sql:variable("@transportInfo") as last into (/ws:MT_RU_IncomingConsignmentRequest/ws:data/merc:delivery)[1]')

		--@transportStorageType
		SET @Message.modify('
			declare namespace ws="urn:pepsico:ru:mercury:2.0:Service:ERPOut";
			declare namespace merc="urn:pepsico:ru:mercury:2.0:DT:MercuryG2BApplications";
			insert sql:variable("@transportStorageType") as last into (/ws:MT_RU_IncomingConsignmentRequest/ws:data/merc:delivery)[1]')

		--@shipmentRoute
		SET @Message.modify('
			declare namespace ws="urn:pepsico:ru:mercury:2.0:Service:ERPOut";
			declare namespace merc="urn:pepsico:ru:mercury:2.0:DT:MercuryG2BApplications";
			insert sql:variable("@shipmentRoute") as last into (/ws:MT_RU_IncomingConsignmentRequest/ws:data/merc:delivery)[1]')

		--@accompanyingForms
		SET @Message.modify('
			declare namespace ws="urn:pepsico:ru:mercury:2.0:Service:ERPOut";
			declare namespace merc="urn:pepsico:ru:mercury:2.0:DT:MercuryG2BApplications";
			insert sql:variable("@accompanyingForms") as last into (/ws:MT_RU_IncomingConsignmentRequest/ws:data/merc:delivery)[1]')

		--Вставка в сообщение результата приемки
		SET @Message.modify('
			declare namespace ws="urn:pepsico:ru:mercury:2.0:Service:ERPOut";
			insert sql:variable("@deliveryFacts") as last into (/ws:MT_RU_IncomingConsignmentRequest/ws:data)[1]')

		IF (@HasDiscrepancyReport = 1) 
		BEGIN
			--Вставка в сообщение Акта несоответствия
			SET @Message.modify('
				declare namespace ws="urn:pepsico:ru:mercury:2.0:Service:ERPOut";
				insert sql:variable("@discrepancyReport") as last into (/ws:MT_RU_IncomingConsignmentRequest/ws:data)[1]')
		END

		IF(@HasReturnedDelivery = 1)
		BEGIN
			-- Копируем часть из delivery для returnedDelivery
			;WITH XMLNAMESPACES
			(
					'urn:pepsico:ru:mercury:2.0:Service:ERPOut' as ws,
					'urn:pepsico:ru:mercury:2.0:DT:MercuryG2BApplications' AS merc
			)
			SELECT @delivery = @Message.query('//ws:MT_RU_IncomingConsignmentRequest/ws:data/merc:delivery/*')

			-- Вставляем delivery в returnedDelivery
			SET @returnedDelivery.modify('
				declare namespace ws="urn:pepsico:ru:mercury:2.0:Service:ERPOut";
				declare namespace merc="urn:pepsico:ru:mercury:2.0:DT:MercuryG2BApplications";
				insert sql:variable("@delivery") as last into (/merc:returnedDelivery)[1]')

		--	select @returnedDelivery

			-- Меняем returnedVolume
			IF(@returnedVolume IS NOT NULL)
				SET @returnedDelivery.modify('
					declare namespace merc="urn:pepsico:ru:mercury:2.0:DT:MercuryG2BApplications";
					declare namespace vetd="urn:pepsico:ru:mercury:2.0:DT:VetDocument";
					replace value of 
						 (/merc:returnedDelivery/vetd:consignment/vetd:volume/text())[1] 
					with sql:variable("@returnedVolume")')

			--Вставка в сообщение Сведения о возвращаемой партии (возвратном ВСД)
			SET @Message.modify('
				declare namespace ws="urn:pepsico:ru:mercury:2.0:Service:ERPOut";
				insert sql:variable("@returnedDelivery") as last into (/ws:MT_RU_IncomingConsignmentRequest/ws:data)[1]')
		END

		IF(@Debug = 1)
			SELECT 
				@ScriptType as ScriptType,
				@vetDocument as vetDocument,
				@Message as OutMessage,
				@consignor as consignor,
				@consignee as consignee,
				@consignment as consignment,
				@broker as [broker],
				@volume as volume,
				@transportInfo as transportInfo,
				@transportStorageType as transportStorageType,
				@shipmentRoute as shipmentRoute,
				@accompanyingForms as accompanyingForms,
				@deliveryFacts as deliveryFacts,
				@HasDiscrepancyReport as HasDiscrepancyReport,
				@discrepancyReport as discrepancyReport,
				@HasReturnedDelivery as HasReturnedDelivery,
				@returnedDelivery as returnedDelivery,
				@returnedVolume as returnedVolume,
				@UpdateNumberKU as UpdateNumberKU,
				@Batch_BatchID as Batch_BatchID, 
				@NumberKU as NumberKU

		--------------------------------------------------------------------------------------------------
		--	Исправление косяка SAP-XI
		--------------------------------------------------------------------------------------------------
		SET @Message = CAST(REPLACE(CAST(@Message as varchar(MAX)),'http://api.vetrf.ru/schema/cdm/base','urn:pepsico:ru:mercury:2.0:DT:Dictionary') as XML)
		--------------------------------------------------------------------------------------------------

		--выполняем валидацию XML файла
		IF EXISTS(SELECT 1 FROM sys.xml_schema_collections WHERE name = N'XSD_XI_Mercury_2_0')
		BEGIN TRY
			SET @Message = CAST(@Message AS xml(DOCUMENT XSD_XI_Mercury_2_0))
		END TRY
		BEGIN CATCH
			SET @ErrorMessage  = CONCAT('Ошибка валидации сформированного xml в [prc_MERC_GenerateXml_PIC_V20]: ', ISNULL(ERROR_MESSAGE(), 'Ошибка валидации xml'))
			RETURN 50001
		END CATCH
	END TRY
	BEGIN CATCH
		SET @ErrorMessage  = CONCAT('Ошибка в [prc_MERC_GenerateXml_PIC_V20]: ', ISNULL(ERROR_MESSAGE(), 'Непонятная ошибка.'))
		RETURN 50001
	END CATCH
/*
	EXEC prc_MERC_GenerateXml_PIC_V20	
*/
	--SELECT @Message
	SELECT @OutMessage = @Message
	RETURN 0

	SET NOCOUNT OFF;
END
GO