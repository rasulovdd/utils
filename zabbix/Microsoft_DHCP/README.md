# Мониторинг DHCP‑сервера Microsoft через Zabbix

Этот шаблон использует командлеты PowerShell для однократного получения всей информации о Microsoft DHCP Server и отправки её на сервер/прокси Zabbix в формате JSON.
    
    Свободно IP ({#SCOPEID})
    Занято IP ({#SCOPEID})
    % использования ({#SCOPEID})
    Зарезервировано IP {#SCOPEID}

## Требования

1. DHCP сервер в Windows

2. Zabbix agent2 

3. Скрипт powershell zabbix_dhcp_scope.ps1

## Установка

1. Импортируйте шаблон Template_App_Microsoft_DHCP.yaml

2. Установите Zabbix agent2 на сервер.

3. Скопируйте zabbix_dhcp_scope.ps1 в папку агента "C:\Program Files\Zabbix Agent 2\"

4. Добавьте следующую строку в файл конфигурации агента Zabbix и перезапустите службу 
    
    ```
    UnsafeUserParameters=1 
    AllowKey=system.run[*]
    ```

## Шаблон 

- Template_App_Microsoft_DHCP.yaml
