# Автоматическая установка и настройка мониторинга GPU и Docker для Zabbix agent > 6

## Установка. (нужны права sudo)
  ```bash
  bash <(curl -fsSL https://raw.githubusercontent.com/rasulovdd/utils/main/zabbix/install_mon.sh)
  ```

## Проверка 

  ```bash
  zabbix_agent2 -t gpu.load
  zabbix_agent2 -t gpu.vram
  zabbix_agent2 -t docker.running
  # если все по 0 значит пользователю zabbix не хватает права
  ```
  
  Добавляем пользователя zabbix в группу docker (если предедущие команды вернули 0)
  ```bash
  sudo usermod -aG docker zabbix
  ```

## Добавление шаблона в zabbix сервер 
  1. Скачайте шаблон Template App GPU and Docker.yaml
  2. Zabbix -> Templates -> Import. Выберите файл и нажмите открыть
  3. Добавьте этот шаблон к серверу которую хотите мониторить


## Шаблоны 

  1. Template_App_GPU_and_Docker.yaml - мониторинг GPU и докер
  2. Template_App_Microsoft_DHCP.yaml - мониторинг DCHP


# Template_App_Microsoft_DHCP

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
