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


## Шаблон 

- Template_App_GPU_and_Docker.yaml
