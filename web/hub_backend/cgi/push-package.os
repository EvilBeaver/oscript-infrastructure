#!/usr/bin/oscript-cgi

#Использовать fs
#Использовать json

Перем ПарсерJSON;
Перем КаталогПубликации;

Функция ПолучитьСоединениеGithub()
	Сервер = "https://api.github.com";
	_Соединение = Новый HTTPСоединение(Сервер);
	
	Возврат _Соединение;
КонецФункции

Функция ПолучитьЗаголовкиЗапросаGithub(ТокенАвторизации)
	
	_Заголовки = Новый Соответствие();
	_Заголовки.Вставить("Accept", "application/vnd.github.v3+json");
	_Заголовки.Вставить("User-Agent", "oscript-library-autobuilder");
	
	_Заголовки.Вставить("Authorization", СтрШаблон("token %1", ТокенАвторизации));
	
	Возврат _Заголовки;
	
КонецФункции

Функция ПолучитьИмяПакетаИзИмениФайла(ИмяФайла)
	
	ИмяПакетаМассив = СтрРазделить(ИмяФайла, "-");
	ИмяПакета = "";
	Для сч = 0 По ИмяПакетаМассив.ВГраница() - 1 Цикл
		ИмяПакета = ИмяПакета + ИмяПакетаМассив[сч] + "-";
	КонецЦикла;
	ИмяПакета = Лев(ИмяПакета, СтрДлина(ИмяПакета) - 1);
	
	Возврат ИмяПакета;
	
КонецФункции

Функция ПолучитьИмяПользователяПоТокенуАвторизации(ТокенАвторизации)
	
	Соединение = ПолучитьСоединениеGithub();
	РесурсРепозиторий = "/user";
	Заголовки = ПолучитьЗаголовкиЗапросаGithub(ТокенАвторизации);
	ЗапросРепозиторий = Новый HTTPЗапрос(РесурсРепозиторий, Заголовки);
	
	ОтветРепозиторий  = Соединение.Получить(ЗапросРепозиторий);
	ТелоОтвета = ОтветРепозиторий.ПолучитьТелоКакСтроку();
	
	Если ОтветРепозиторий.КодСостояния <> 200 Тогда
		ВывестиЗаголовок("Status", "401");
		ВызватьИсключение ТелоОтвета;
	КонецЕсли;
	
	ДанныеОтвета = ПарсерJSON.ПрочитатьJSON(ТелоОтвета);
	АвторизованныйПользователь = ДанныеОтвета["login"];
	
	Возврат АвторизованныйПользователь;
	
КонецФункции

Процедура ПроверитьЧтоПользовательИмеетПраваОтправкиВРепозиторий(ИмяПользователя, ИмяРепозитория)
	
	// TODO: Системный токен
	ТокенАвторизации = ВебЗапрос.ENV["HTTP_OAUTH_TOKEN"];
	
	Соединение = ПолучитьСоединениеGithub();
	РесурсРепозиторий = СтрШаблон("/repos/oscript-library/%1/collaborators", ИмяРепозитория);
	Заголовки = ПолучитьЗаголовкиЗапросаGithub(ТокенАвторизации);
	ЗапросРепозиторий = Новый HTTPЗапрос(РесурсРепозиторий, ПолучитьЗаголовкиЗапросаGithub(ТокенАвторизации));
	
	ОтветРепозиторий  = Соединение.Получить(ЗапросРепозиторий);
	ТелоОтвета = ОтветРепозиторий.ПолучитьТелоКакСтроку();
	
	Если ОтветРепозиторий.КодСостояния <> 200 Тогда
		ВывестиЗаголовок("Status", "500");
		ВызватьИсключение ТелоОтвета;
	КонецЕсли;
	
	ДанныеОтвета = ПарсерJSON.ПрочитатьJSON(ТелоОтвета);
	
	Для Каждого ДанныеКоллаборатора Из ДанныеОтвета Цикл
		Если ДанныеКоллаборатора["login"] = ИмяПользователя И ДанныеКоллаборатора["permissions"]["push"] Тогда
			ПользовательИмеетПраваОтправки = Истина;
		КонецЕсли;
	КонецЦикла;
	
	Если НЕ ПользовательИмеетПраваОтправки Тогда
		ВывестиЗаголовок("Status", "401");
		ВызватьИсключение "Пользователь не имеет права отправки в репозиторий пакета";
	КонецЕсли;
	
КонецПроцедуры

Процедура Инициализация()
	ПарсерJSON = Новый ПарсерJSON;
	
	СистемнаяИнформация = Новый СистемнаяИнформация;
	КаталогПубликации = СистемнаяИнформация.ПолучитьПеременнуюСреды("PATH_TO_OSCRIPT_HUB");
	Если НЕ ЗначениеЗаполнено(КаталогПубликации) Тогда
		КаталогПубликации = "/var/www/hub.oscript.io/download";
	КонецЕсли;
	
	ВывестиЗаголовок("Content-type", "text/html; charset=utf-8");
	
КонецПроцедуры

////////////////////////////////////

Инициализация();

ТокенАвторизации = ВебЗапрос.ENV["HTTP_OAUTH_TOKEN"];
ДанныеФайла = ВебЗапрос.ПолучитьТелоКакДвоичныеДанные();
ИмяФайла = ВебЗапрос.ENV["HTTP_FILE_NAME"];

АвторизованныйПользователь = ПолучитьИмяПользователяПоТокенуАвторизации(ТокенАвторизации);

ИДПакета = ПолучитьИмяПакетаИзИмениФайла(ИмяФайла);
ПроверитьЧтоПользовательИмеетПраваОтправкиВРепозиторий(АвторизованныйПользователь, ИДПакета);

////////////////

Сообщить(ИмяФайла);

ПутьККаталогуПакета = ОбъединитьПути(КаталогПубликации, ИДПакета);
Сообщить(ПутьККаталогуПакета);
ФС.ОбеспечитьКаталог(ПутьККаталогуПакета);

ДанныеФайла.Записать(ОбъединитьПути(ПутьККаталогуПакета, ИмяФайла));
ДанныеФайла.Записать(ОбъединитьПути(ПутьККаталогуПакета, ИДПакета + ".ospx"));
