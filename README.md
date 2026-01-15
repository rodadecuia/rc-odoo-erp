# RC ODOO ERP
Erp baseado no oddo opensource

## Como rodar com Docker Compose

Este projeto inclui uma configuração do Docker Compose para rodar o Odoo 18 com PostgreSQL.

### Pré-requisitos

- Docker
- Docker Compose

### Passos para iniciar

1. Clone o repositório (se ainda não o fez).
2. Navegue até a pasta raiz do projeto.
3. Execute o seguinte comando para iniciar os containers:

```bash
docker-compose up -d
```

4. O Odoo estará acessível em `http://localhost:8069`.

### Credenciais Padrão

- **Banco de Dados:**
  - Usuário: `odoo`
  - Senha: `odoo`

### Estrutura de Pastas

- `docker-compose.yml`: Arquivo de definição dos serviços.
- `config/`: Contém o arquivo de configuração `odoo.conf`.
- `addons/`: Pasta mapeada para `/mnt/extra-addons` para adicionar módulos personalizados.
