# RC ODOO ERP
Erp baseado no oddo opensource

## Como rodar com Docker Compose

Este projeto inclui uma configuração do Docker Compose para rodar o Odoo 18 com PostgreSQL.

### Pré-requisitos

- Docker
- Docker Compose
- Git

### Passos para iniciar

1. Clone o repositório (se ainda não o fez).
2. Navegue até a pasta raiz do projeto.
3. Inicialize os módulos da OCA (Odoo Community Association):

   Se você estiver no Linux/Mac ou usando Git Bash no Windows:
   ```bash
   chmod +x setup_oca.sh
   ./setup_oca.sh
   ```
   
   Isso irá baixar os repositórios necessários (l10n-brazil, account-fiscal-rule, etc.) como submódulos git na pasta `oca_addons`.

4. Execute o seguinte comando para iniciar os containers:

```bash
docker-compose up -d --build
```

5. O Odoo estará acessível em `http://localhost:8069`.

### Credenciais Padrão

- **Banco de Dados:**
  - Usuário: `odoo`
  - Senha: `odoo`

### Estrutura de Pastas

- `docker-compose.yml`: Arquivo de definição dos serviços.
- `config/`: Contém o arquivo de configuração `odoo.conf`.
- `addons/`: Pasta mapeada para `/mnt/extra-addons` para adicionar módulos personalizados.
- `oca_addons/`: Pasta mapeada para `/mnt/oca-addons` para módulos da OCA.
- `requirements.txt`: Lista de dependências Python adicionais.

### Módulos OCA Incluídos

O script `setup_oca.sh` configura automaticamente os seguintes repositórios principais para a localização brasileira e funcionalidades extras:

- l10n-brazil
- account-fiscal-rule
- reporting-engine
- server-ux
- mis-builder
- web
- account-financial-reporting
- account-financial-tools
- partner-contact
- stock-logistics-workflow
- sale-workflow
- purchase-workflow
- bank-payment
- server-tools
- queue
- contract

**Nota:** Certifique-se de que os módulos baixados são compatíveis com a versão 18.0 do Odoo. O script tenta usar a branch `18.0` por padrão.
