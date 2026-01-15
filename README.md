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
- `oca_addons/`: Pasta mapeada para `/mnt/oca-addons` para módulos da OCA (Odoo Community Association).
- `requirements.txt`: Lista de dependências Python adicionais (ex: `pytrustnfe`).

### Adicionando Módulos OCA Brasil

Para utilizar a localização brasileira, você deve adicionar os repositórios da OCA dentro da pasta `oca_addons`. Recomendamos o uso de submodules do git.

Exemplo:

```bash
cd oca_addons
git submodule add -b 18.0 https://github.com/OCA/l10n-brazil.git
# Adicione outros repositórios conforme necessário
```

**Nota:** Certifique-se de que os módulos são compatíveis com a versão 18.0 do Odoo.
