-- выбор списка уникальных заполненных тегов в XML
-- или кол-во уникальных заполненных тегов

DECLARE @xml xml

-- тег <?xml version="1.0" encoding="utf-8"?>
-- надо вырезать из xml если он там будет
SET @xml = '
<?mso-infoPathSolution name="urn:schemas-microsoft-com:office:infopath:Mnbne-1nck-1nb-mhe:-myXSD-2008-10-03T07-39-47" solutionVersion="1.0.0.1352" productVersion="12.0.0.0" PIVersion="1.0.0.0" href="http://second2/sites/reviews/FormServerTemplates/%D0%9D%D0%BE%D0%B2%D0%BE%D0%B5%20%D1%81%D0%BE%D0%B3%D0%BB%D0%B0%D1%81%D0%BE%D0%B2%D0%B0%D0%BD%D0%B8%D0%B5.xsn" initialView="Согласование в работе"?>
<?mso-application progid="InfoPath.Document" versionProgid="InfoPath.Document.2"?>
<?mso-infoPath-file-attachment-present?>
<my:моиПоля xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xhtml="http://www.w3.org/1999/xhtml" xmlns:d="http://schemas.microsoft.com/office/infopath/2003/ado/dataFields" xmlns:dfs="http://schemas.microsoft.com/office/infopath/2003/dataFormSolution" xmlns:tns="http://tempuri.org/" xmlns:_xdns0="http://schemas.microsoft.com/office/infopath/2003/changeTracking" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:diffgr="urn:schemas-microsoft-com:xml-diffgram-v1" xmlns:msdata="urn:schemas-microsoft-com:xml-msdata" xmlns:http="http://schemas.xmlsoap.org/wsdl/http/" xmlns:soap12="http://schemas.xmlsoap.org/wsdl/soap12/" xmlns:mime="http://schemas.xmlsoap.org/wsdl/mime/" xmlns:soapenc="http://schemas.xmlsoap.org/soap/encoding/" xmlns:tm="http://microsoft.com/wsdl/mime/textMatching/" xmlns:ns1="http://schemas.xmlsoap.org/wsdl/soap/" xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/" xmlns:my="http://schemas.microsoft.com/office/infopath/2003/myXSD/2008-10-03T07:39:47" xmlns:xd="http://schemas.microsoft.com/office/infopath/2003" xml:lang="ru-RU">
  <my:название_документа>Внешний приход с МКН 8839386-001; 8839394-001; 8852143-002; 8852138-001; 8857582-001; 8857577-001; 8858017-00; 8858017-001; 8885762-001; 8870225-001</my:название_документа>
  <my:версия_документа />
  <my:комментарий>
    <html xmlns="http://www.w3.org/1999/xhtml" xml:space="preserve">
      <div>Добрый день <br />Коллеги, прошу Вас подтвердить списание за счет склада отправителя. Письма-согласование во вложении. </div>
<div>
<table border="0" width="465" cellpadding="0" cellspacing="0" style="width:350pt;border-collapse:collapse">
<colgroup>
<col width="98" style="width:74pt" />
<col width="94" style="width:71pt" />
<col width="213" style="width:160pt" />
<col width="60" style="width:45pt" />
<tbody>
<tr height="20" style="height:15pt">
<td width="98" height="20" style="border-top:windowtext 0.5pt solid;height:15pt;border-right:windowtext 0.5pt solid;width:74pt;border-bottom:windowtext 0.5pt solid;padding-bottom:0cm;padding-top:0cm;border-left:windowtext 0.5pt solid;background-color:transparent" class="xl70"><font face="Calibri">8839386-001</font></td>
<td align="right" width="94" style="border-top:windowtext 0.5pt solid;border-right:windowtext 0.5pt solid;width:71pt;border-bottom:windowtext 0.5pt solid;padding-bottom:0cm;padding-top:0cm;border-left:#f0f0f0;background-color:transparent" class="xl71"><font face="Calibri">90152181213</font></td>
<td width="213" style="border-top:windowtext 0.5pt solid;border-right:#f0f0f0;width:160pt;border-bottom:windowtext 0.5pt solid;padding-bottom:0cm;padding-top:0cm;border-left:windowtext;background-color:transparent" class="xl69"><font face="Calibri">Молоко ультрапаст М 3.2% 1х12х950г TBAB 9мес</font></td>
<td width="60" style="border-top:windowtext 0.5pt solid;border-right:windowtext 0.5pt solid;width:45pt;border-bottom:windowtext 0.5pt solid;padding-bottom:0cm;padding-top:0cm;border-left:windowtext 0.5pt solid;background-color:transparent" class="xl68"><font face="Calibri">3 кор</font></td></tr>
<tr height="20" style="height:15pt">
<td height="20" style="border-top:windowtext;height:15pt;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;border-left:windowtext 0.5pt solid;background-color:transparent" class="xl70"><font face="Calibri">8839394-001</font></td>
<td align="right" style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;padding-bottom:0cm;padding-top:0cm;border-left:#f0f0f0;background-color:transparent" class="xl71"><font face="Calibri">90152291213</font></td>
<td style="border-top:windowtext;border-right:#f0f0f0;border-bottom:windowtext 0.5pt solid;border-left:windowtext;background-color:transparent" class="xl69"><font face="Calibri">Мол ультрап 33коровы 1х12х950г 2,5% ТВАВ 9 мес</font></td>
<td style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;border-left:windowtext 0.5pt solid;background-color:transparent" class="xl68"><span style="" lang="EN-US"><font face="Calibri">8 кор</font></span></td></tr>
<tr height="20" style="height:15pt">
<td height="20" style="border-top:windowtext;height:15pt;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;border-left:windowtext 0.5pt solid;background-color:transparent" class="xl70"><font face="Calibri">8852143-002</font></td>
<td align="right" style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;padding-bottom:0cm;padding-top:0cm;border-left:#f0f0f0;background-color:transparent" class="xl71"><font face="Calibri">90152181213</font></td>
<td style="border-top:windowtext;border-right:#f0f0f0;border-bottom:windowtext 0.5pt solid;padding-bottom:0cm;padding-top:0cm;border-left:windowtext;background-color:transparent" class="xl69"><font face="Calibri">Молоко ультрапаст М 3.2% 1х12х950г TBAB 9мес</font></td>
<td style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;padding-bottom:0cm;padding-top:0cm;border-left:windowtext 0.5pt solid;background-color:transparent" class="xl68"><span style="" lang="EN-US"><font face="Calibri">1 кор</font></span></td></tr>
<tr height="20" style="height:15pt">
<td height="20" style="border-top:windowtext;height:15pt;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;padding-bottom:0cm;padding-top:0cm;border-left:windowtext 0.5pt solid;background-color:transparent" class="xl70"><font face="Calibri">8852138-001</font></td>
<td align="right" style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;border-left:#f0f0f0;background-color:transparent" class="xl71"><font face="Calibri">90152301213</font></td>
<td style="border-top:windowtext;border-right:#f0f0f0;border-bottom:windowtext 0.5pt solid;border-left:windowtext;background-color:transparent" class="xl69"><font face="Calibri">Молоко ультрап 33 коровы 3.2%1х12х950гTBAВ9мес</font></td>
<td style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;border-left:windowtext 0.5pt solid;background-color:transparent" class="xl68"><font face="Calibri">1 кор</font></td></tr>
<tr height="20" style="height:15pt">
<td height="20" style="border-top:windowtext;height:15pt;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;padding-bottom:0cm;padding-top:0cm;border-left:windowtext 0.5pt solid;background-color:transparent" class="xl70"><font face="Calibri">8857582-001</font></td>
<td align="right" style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;border-left:#f0f0f0;background-color:transparent" class="xl71"><font face="Calibri">90292401813</font></td>
<td style="border-top:windowtext;border-right:#f0f0f0;border-bottom:windowtext 0.5pt solid;border-left:windowtext;background-color:transparent" class="xl69"><font face="Calibri">Кокт мол стер Чудо Детки клубн 3.2% 1х18х200мл ТВА</font></td>
<td style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;border-left:windowtext 0.5pt solid;background-color:transparent" class="xl68"><font face="Calibri">29 кор</font></td></tr>
<tr height="20" style="height:15pt">
<td height="20" style="border-top:windowtext;height:15pt;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;border-left:windowtext 0.5pt solid;background-color:transparent" class="xl70"><font face="Calibri">8857577-001</font></td>
<td align="right" style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;padding-bottom:0cm;padding-top:0cm;border-left:windowtext;background-color:transparent" class="xl68"><font face="Calibri">90118371213</font></td>
<td style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;padding-bottom:0cm;padding-top:0cm;border-left:windowtext;background-color:transparent" class="xl68"><font face="Calibri">Молоко ультрап Веселый молочник 3.2% 1х12х950г TBA</font></td>
<td style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;padding-bottom:0cm;padding-top:0cm;border-left:windowtext;background-color:transparent" class="xl68"><font face="Calibri">1 кор</font></td></tr>
<tr height="20" style="height:15pt">
<td height="20" style="border-top:windowtext;height:15pt;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;border-left:windowtext 0.5pt solid;background-color:transparent" class="xl70"><span style=""><font face="Calibri">8858017-002</font></span></td>
<td align="right" style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;border-left:windowtext;background-color:transparent" class="xl68"><span style=""><font face="Calibri">90290601013</font></span></td>
<td style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;border-left:windowtext;background-color:transparent" class="xl68"><span style=""><font face="Calibri">Нап к/м Фругурт 1,5% 1x10x950г ТR TwCap Клуб</font></span></td>
<td style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;border-left:windowtext;background-color:transparent" class="xl68"><span style=""><font face="Calibri">1 кор</font></span></td></tr>
<tr height="20" style="height:15pt">
<td height="20" style="border-top:windowtext;height:15pt;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;padding-bottom:0cm;padding-top:0cm;border-left:windowtext 0.5pt solid;background-color:transparent" class="xl70"><span style=""><font face="Calibri">8858017-001</font></span></td>
<td align="right" style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;border-left:windowtext;background-color:transparent" class="xl68"><span style=""><font face="Calibri">90152631013</font></span></td>
<td style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;border-left:windowtext;background-color:transparent" class="xl68"><span style=""><font face="Calibri">Продукт к/м Снежок ДвД 2.5% 1х10х475г ТR</font></span></td>
<td style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;border-left:windowtext;background-color:transparent" class="xl68"><span style=""><font face="Calibri">1 кор</font></span></td></tr>
<tr height="18" style="height:13.5pt">
<td height="18" style="border-top:windowtext;height:13.5pt;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;border-left:windowtext 0.5pt solid;background-color:transparent" class="xl68"><font face="Calibri">8885762-001</font></td>
<td align="right" style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;padding-bottom:0cm;padding-top:0cm;border-left:windowtext;background-color:transparent" class="xl68"><font face="Calibri">90152301213</font></td>
<td style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;padding-bottom:0cm;padding-top:0cm;border-left:windowtext;background-color:transparent" class="xl68"><font face="Calibri">Молоко ультрап 33 коровы 3.2%1х12х950гTBAВ9мес</font></td>
<td style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;padding-bottom:0cm;padding-top:0cm;border-left:windowtext;background-color:transparent" class="xl68"><font face="Calibri">1 кор</font></td></tr>
<tr height="18" style="height:13.5pt">
<td height="18" style="border-top:windowtext;height:13.5pt;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;padding-bottom:0cm;padding-top:0cm;border-left:windowtext 0.5pt solid;background-color:transparent" class="xl68"><font face="Calibri">8870225-001</font></td>
<td align="right" style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;border-left:windowtext;background-color:transparent" class="xl68"><font face="Calibri">90292401813</font></td>
<td style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;border-left:windowtext;background-color:transparent" class="xl68"><font face="Calibri">Кокт мол стер Чудо Детки клубн 3.2% 1х18х200мл ТВА</font></td>
<td style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:windowtext 0.5pt solid;border-left:windowtext;background-color:transparent" class="xl68"><font face="Calibri">9 кор</font></td></tr></tbody></colgroup></table></div>
<table border="0" width="192" cellpadding="0" cellspacing="0" style="width:145pt;border-collapse:collapse">
<colgroup>
<col width="98" style="width:74pt" />
<col width="94" style="width:71pt" />
<tbody>
<tr height="20" style="height:15pt">
<td width="98" height="20" style="border-top:windowtext 0.5pt solid;height:15pt;border-right:windowtext 0.5pt solid;width:74pt;border-bottom:windowtext 0.5pt solid;border-left:windowtext 0.5pt solid;background-color:transparent" class="xl68"><font face="Calibri">ЦФО</font></td>
<td width="94" style="border-top:windowtext 0.5pt solid;border-right:windowtext 0.5pt solid;width:71pt;border-bottom:windowtext 0.5pt solid;border-left:windowtext;background-color:transparent" class="xl69"><font face="Calibri">2320320106</font></td></tr>
<tr height="20" style="height:15pt">
<td height="20" style="border-top:windowtext;height:15pt;border-right:windowtext 0.5pt solid;border-bottom:#f0f0f0;border-left:windowtext 0.5pt solid;background-color:transparent" class="xl70"><font face="Calibri">НЗиП</font></td>
<td align="right" style="border-top:windowtext;border-right:windowtext 0.5pt solid;border-bottom:#f0f0f0;border-left:windowtext;background-color:transparent" class="xl70"><font face="Calibri">1050704</font></td></tr></tbody></colgroup></table></html>
  </my:комментарий>
  <my:утверждающий_сотрудник />
  <my:сотрудники-получатели />
  <my:начало>2016-01-11</my:начало>
  <my:окончание>2016-01-14</my:окончание>
  <my:время_окончания>17:00</my:время_окончания>
  <my:дней_до_окончания>1</my:дней_до_окончания>
  <my:ИмяФайла>DOC0468432</my:ИмяФайла>
  <my:действие_после_окончания>1</my:действие_после_окончания>
  <my:документ_на_согласование>
    <my:файл_на_согласование xsi:nil="true" />
  </my:документ_на_согласование>
  <my:группа_согласующих_сотрудников>
    <my:согласующий_сотрудник>Шаган Татьяна Николаевна</my:согласующий_сотрудник>
    <my:PUID_согласующего_сотрудника>14577</my:PUID_согласующего_сотрудника>
    <my:адрес_почты>Tatyana.Shagan@pepsico.com</my:адрес_почты>
    <my:логин>CWWPVT\40180467</my:логин>
    <my:решение>1</my:решение>
    <my:замечания />
    <my:решение_отображение>согласен(на)</my:решение_отображение>
    <my:дата_решения>11.01.2016 12:24</my:дата_решения>
    <my:TitleName>Руководитель департамента</my:TitleName>
    <my:com-pic-group />
    <my:hlink1 />
    <my:hlink2 />
    <my:hlink3 />
    <my:namelink1 />
    <my:namelink2 />
    <my:namelink3 />
    <my:fil-pic-group />
    <my:fil-pic-print />
  </my:группа_согласующих_сотрудников>
  <my:выбор_предприятия_согласующего>1287</my:выбор_предприятия_согласующего>
  <my:выбор-согласующего_сотрудника>14577</my:выбор-согласующего_сотрудника>
  <my:группа_получателей_уведомлений>
    <my:получатель_уведомления>Мельникова Елена Михайловна</my:получатель_уведомления>
    <my:PUID_получателя_уведомления>13981</my:PUID_получателя_уведомления>
    <my:получ_логин>CWWPVT\40197626</my:получ_логин>
    <my:адрес_почты_получ>Elena.Melnikova@pepsico.com</my:адрес_почты_получ>
  </my:группа_получателей_уведомлений>
  <my:выбор-предприятия_получателя>1287</my:выбор-предприятия_получателя>
  <my:выбор-сотрудника_получателя>13981</my:выбор-сотрудника_получателя>
  <my:Статус>Approve</my:Статус>
  <my:инициатор>Ахматова Адина Сапаралыевна</my:инициатор>
  <my:статус_отображение />
  <my:решение_согласующий_сотрудник />
  <my:решение_принятое_решение />
  <my:решение_замечания />
  <my:инициатор_логин>CWWPVT\40255777</my:инициатор_логин>
  <my:утв_сотр_имя />
  <my:действие_при_получении>1</my:действие_при_получении>
  <my:утв_сотр_решение />
  <my:утв_сотр_замечания />
  <my:итоговое_резюме>1</my:итоговое_резюме>
  <my:номер_заявки />
  <my:инициатор_заявки />
  <my:контакты />
  <my:предприятие />
  <my:ссылки>
    <my:Ссылка_текст />
    <my:Ссылка_адрес />
  </my:ссылки>
  <my:AppId />
  <my:подразделение />
  <my:статус_коммент />
  <my:строка_поиска_ФИО>шаган</my:строка_поиска_ФИО>
  <my:Результат_поиска>14577</my:Результат_поиска>
  <my:дата_решения_отображение />
  <my:Ошибка_SQL_текст />
  <my:дата_утверждения />
  <my:дата_решения_инициатора>11.01.2016 12:49</my:дата_решения_инициатора>
  <my:группа1 />
  <my:select-titlename>Руководитель департамента</my:select-titlename>
  <my:resolve-titlename />
  <my:utvcompic />
  <my:initcompic>
    <my:группа3 />
  </my:initcompic>
  <my:инициатор_PUID>26338</my:инициатор_PUID>
  <my:ViewerLogin>CWWPVT\40255777</my:ViewerLogin>
  <my:ViewerPUID>26338</my:ViewerPUID>
  <my:viewdoc />
  <my:vhlink1 />
  <my:vhlink2 />
  <my:vhlink3 />
  <my:vnamelink1 />
  <my:vnamelink2 />
  <my:vnamelink3 />
  <my:flinkGroup>
    <my:UploadFile>x0lGQRQAAAABAAAAAAAAAAAAAAACAAAAMAAAAA==</my:UploadFile>
    <my:UploadHide />
    <my:hlink>http://second2/sites/reviews/Attachments/DOC0468432/F0725119/МКН 24043.38.doc</my:hlink>
    <my:namelink>МКН 24043.38.doc</my:namelink>
  </my:flinkGroup>
  <my:flinkGroup xmlns:my="http://schemas.microsoft.com/office/infopath/2003/myXSD/2008-10-03T07:39:47">
    <my:UploadFile xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">x0lGQRQAAAABAAAAAAAAAAAAAAACAAAAMAAAAA==</my:UploadFile>
    <my:UploadHide />
    <my:hlink>http://second2/sites/reviews/Attachments/DOC0468432/F0725121/RE  Согласовать внешний приход с МКН (1).msg</my:hlink>
    <my:namelink>RE  Согласовать внешний приход с МКН (1).msg</my:namelink>
  </my:flinkGroup>
  <my:flinkGroup xmlns:my="http://schemas.microsoft.com/office/infopath/2003/myXSD/2008-10-03T07:39:47">
    <my:UploadFile xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">x0lGQRQAAAABAAAAAAAAAAAAAAACAAAAMAAAAA==</my:UploadFile>
    <my:UploadHide />
    <my:hlink>http://second2/sites/reviews/Attachments/DOC0468432/F0725123/RE  Согласовать внешний приход с МКН (2).msg</my:hlink>
    <my:namelink>RE  Согласовать внешний приход с МКН (2).msg</my:namelink>
  </my:flinkGroup>
  <my:flinkGroup xmlns:my="http://schemas.microsoft.com/office/infopath/2003/myXSD/2008-10-03T07:39:47">
    <my:UploadFile xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">x0lGQRQAAAABAAAAAAAAAAAAAAACAAAAMAAAAA==</my:UploadFile>
    <my:UploadHide />
    <my:hlink>http://second2/sites/reviews/Attachments/DOC0468432/F0725125/RE  Согласовать внешний приход с МКН (3).msg</my:hlink>
    <my:namelink>RE  Согласовать внешний приход с МКН (3).msg</my:namelink>
  </my:flinkGroup>
  <my:flinkGroup xmlns:my="http://schemas.microsoft.com/office/infopath/2003/myXSD/2008-10-03T07:39:47">
    <my:UploadFile xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">x0lGQRQAAAABAAAAAAAAAAAAAAACAAAAMAAAAA==</my:UploadFile>
    <my:UploadHide />
    <my:hlink>http://second2/sites/reviews/Attachments/DOC0468432/F0725127/RE  Согласовать внешний приход с МКН.msg</my:hlink>
    <my:namelink>RE  Согласовать внешний приход с МКН.msg</my:namelink>
  </my:flinkGroup>
  <my:flinkGroup xmlns:my="http://schemas.microsoft.com/office/infopath/2003/myXSD/2008-10-03T07:39:47">
    <my:UploadFile xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">x0lGQRQAAAABAAAAAAAAAAAAAAACAAAAMAAAAA==</my:UploadFile>
    <my:UploadHide />
    <my:hlink>http://second2/sites/reviews/Attachments/DOC0468432/F0725131/RE  Согласовать внешнийи приход с МКН.msg</my:hlink>
    <my:namelink>RE  Согласовать внешнийи приход с МКН.msg</my:namelink>
  </my:flinkGroup>
  <my:HFileErText />
  <my:FileErText />
  <my:checkFileEr>false</my:checkFileEr>
  <my:HFileGroup />
  <my:ParentID />
  <my:NullFile>x0lGQRQAAAABAAAAAAAAAAAAAAACAAAAMAAAAA==</my:NullFile>
  <my:UtvHideOpt />
  <my:UtvOption>0</my:UtvOption>
  <my:SelectPattern />
  <my:InitPUID />
  <my:AssistantGroup />
  <my:AssistantInfo />
</my:моиПоля>'
SELECT @xml

;WITH Xml_CTE AS
(
    SELECT
        CAST('/' + node.value('fn:local-name(.)',
            'varchar(100)') AS varchar(100)) AS name,
        node.query('*') AS children,
		node.value('text()[1]','NVARCHAR(MAX)') AS Value
    FROM 
		@xml.nodes('/*') AS roots(node)
	--WHERE		node.value('text()[1]','NVARCHAR(MAX)') IS NOT NULL
    UNION ALL

    SELECT
        CAST(x.name + '/' + 
            node.value('fn:local-name(.)', 'varchar(100)') AS varchar(100)),
        node.query('*') AS children,
		node.value('text()[1]','NVARCHAR(MAX)') AS Value
    FROM 
		Xml_CTE x
		CROSS APPLY x.children.nodes('*') AS child(node)
)
SELECT 
	DISTINCT name -- список уникальных заполненных тегов
	--COUNT(DISTINCT name) -- кол-во уникальных заполненных тегов
	--*
FROM Xml_CTE
WHERE
	Value IS NOT NULL AND
	name not like '/моиПоля/комментарий/%'
OPTION (MAXRECURSION 1000)

