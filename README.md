# Скрипты поддержки инфраструктуры oscript.io

## Вот ду ви вонт

* Коммит в ветку
* Сборка на этой ветке
* Прогон тестов из этой ветки
* Формирование артефактов
* Взять актуальные пакеты из hub.oscript.io/dev-channel и прогнать их тесты на собранном артефакте
    * под Windows
    * под Linux
* Если ветка была develop - положить артефакты в ночную сборку для скачивания на сайте
* Если ветка была master
  * Взять актуальные пакеты из hub.oscript.io/dev-channel и прогнать их тесты на собранном артефакте
    * под Windows
    * под Linux
  * положить артефакты в стабильную сборку на сайте
  * опубликовать артефакты в релизах github
  * опубликовать пакеты Nuget
  * обновить документацию на сайте (лежит в артефактах)
  
  
  Этот документ можно обсуждать и предлагать к нему правки.
