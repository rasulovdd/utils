# utils
Всякая всячина

  # index.html 
  ```bash
  curl -o index.html https://raw.githubusercontent.com/rasulovdd/utils/main/www/index.html
  ```
  # app-config.json
  ```bash
  curl -o index.html https://raw.githubusercontent.com/rasulovdd/utils/main/www/app-config.json
  ```
  после выгрузки не забудьте поменять переменные <br>
  "supportUrl": "https://t.me/yousupport" <br>
  "logoUrl": "https://web.ru/logo.png" <br>
  <br>
  
  # папка ansible: my-project
  ## клонировать весь репозиторий
  ```bash
  git clone https://github.com/rasulovdd/utils.git
  ```
  ## скопировать нужную папку
  ```bash
  cp -r utils/my-project/ .
  ```
  ## удалить остальной репозиторий
  ```bash
  rm -rf utils
  ```
  ## создать свой конфиг и отредактировать
  ```bash
  cd my-project
  cp ansible.cfg.sample ansible.cfg
  nano ansible.cfg
  ```

  ## структура папки
  ```info
  my-project/
  ├── inventory/   # файлы инвентаризации
  ├── playbooks/   # основные плейбуки
  ├── roles/       # роли
  ├── group_vars/  # переменные для групп хостов
  ├── host_vars/   # переменные для отдельных хостов
  ├── files/       # дополнительные файлы
  ├── ansible.cfg  # конфиг файл
  └── ansible.log  # лог файл
  ```
