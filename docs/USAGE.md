# Workstation Ansible - Manual de Uso

Este projeto visa automatizar a configuração do seu ambiente de desenvolvimento. Abaixo estão os detalhes sobre como operar o sistema, personalizar perfis e solucionar problemas.

## Comandos Principais (Makefile)

O arquivo `Makefile` é a interface principal.

*   `make local`: Configura a máquina atual.
*   `make remote IP=<IP> USER=<USER>`: Configura uma máquina remota via SSH.
*   `make tunnel IP=<IP> JUMP_IP=<JUMP_IP>`: Configura uma máquina através de um Bastion Host.
*   `make deps`: Instala dependências do Ansible (roles/collections do Galaxy).
*   `make lint`: Executa verificação de sintaxe nos playbooks.

### Variáveis de Controle

Você pode passar variáveis extras para qualquer comando `make`:

*   `TAGS`: Lista de tags separadas por vírgula para executar apenas partes específicas.
    *   Exemplo: `make local TAGS=zsh,dotfiles`
*   `PROFILE`: Define qual perfil de variáveis carregar (padrão: `default`).
    *   Exemplo: `make local PROFILE=minimal`
*   `DRY`: Se definido (ex: `DRY=1`), executa em modo de simulação (Check Mode), mostrando o que seria alterado sem aplicar nada.

## Perfis (Profiles)

Os perfis definem *o que* será instalado (quais pacotes, quais ferramentas).

1.  **Padrão (`profiles/default.yml`)**: Contém a lista completa de pacotes sugeridos.
2.  **Local (`profiles/local.yml`)**: Este arquivo é ignorado pelo Git. Use-o para suas personalizações.
    *   **Como criar:** Copie o arquivo de exemplo: `cp profiles/local.sample.yml profiles/local.yml`.
    *   Edite `profiles/local.yml` para adicionar ou remover pacotes e sobrescrever configurações.

## Tags Disponíveis

Use tags para agilizar a execução quando quiser alterar apenas um componente:

*   `devtools`: Pacotes base (git, curl, tmux, build-essentials).
*   `languages`: Ambientes de programação (Node, Python, Rust).
    *   `node`, `python`, `rust`: Tags específicas para cada linguagem.
*   `docker`: Instalação do Docker e Docker Compose.
*   `zsh`: Configuração do Shell Zsh, Oh-My-Zsh e Powerlevel10k.
*   `ui`: Interface gráfica (Sway, fontes, temas) - *Geralmente apenas para Linux Desktop*.
*   `editors`: Editores de texto (Neovim, etc).
*   `dotfiles`: Gerenciamento de arquivos de configuração via GNU Stow.

## Estrutura de Pastas Importante

*   `playbooks/roles/`: Contém a lógica de instalação separada por função.
*   `playbooks/roles/*/vars/`: Variáveis específicas por sistema operacional (ex: `Void.yml`, `Debian.yml`). Se sua distribuição não for suportada, você pode adicionar um arquivo aqui.

## Arquitetura de Configuração e Extensão

Este projeto utiliza uma separação clara entre **Pacotes de Sistema** e **Features Complexas**.

### 1. Packages vs. Features

No arquivo de perfil (`profiles/default.yml` ou `profiles/local.yml`), você encontrará dois tipos principais de variáveis para cada role (devtools, ui, languages, etc):

*   **`*_packages` (Listas Simples):**
    *   São listas de pacotes que podem ser instalados diretamente pelo gerenciador de pacotes do sistema (apt, xbps-install, dnf, pacman).
    *   *Exemplo:* `devtools_packages` contém `git`, `curl`, `htop`.
    *   **Uso:** Edite estas listas para adicionar ferramentas simples que já existem nos repositórios da sua distro.

*   **`*_features` (Flags de Lógica Complexa):**
    *   São dicionários de booleanos (`true`/`false`) que ativam scripts de instalação mais complexos (compilação, download de binários, instaladores oficiais como `rustup`).
    *   *Exemplo:* `languages_features.rust: true` não apenas instala um pacote, mas baixa e executa o script oficial do Rustup.
    *   **Uso:** Ative ou desative features inteiras conforme sua necessidade.

### 2. Personalizando (O jeito certo)

Não edite o `profiles/default.yml` diretamente se quiser manter seu fork limpo. Use o `profiles/local.yml`:

```yaml
# profiles/local.yml

# Sobrescreve a lista padrão, adicionando apenas o que eu quero
devtools_packages:
  - git
  - vim  # Prefiro vim ao neovim
  - htop

# Desativa instalação do Node.js, mas mantêm Rust e Python
languages_features:
  node: false
  rust: true
  python: true
```

### 3. Estendendo para sua Distro ou Nova Feature

#### Adicionando suporte a uma nova Distro (ex: Fedora)
Se o Ansible falhar ao não encontrar variáveis para sua distro:
1.  Descubra a família do SO: `ansible localhost -m setup -a "filter=ansible_os_family"` (ex: `RedHat`).
2.  Crie o arquivo de variáveis na role desejada: `playbooks/roles/devtools/vars/RedHat.yml`.
3.  Mapeie os nomes dos pacotes (ex: `python3-devel` no Fedora vs `python3-dev` no Debian).

#### Criando uma Feature Personalizada
Para adicionar uma instalação complexa (ex: instalar o `k9s` via binário):
1.  **No Perfil (`profiles/default.yml`):** Adicione a flag.
    ```yaml
    devtools_features:
      k9s: true
    ```
2.  **Na Task (`playbooks/roles/devtools/tasks/main.yml`):** Adicione a lógica condicional.
    ```yaml
    - name: Baixar k9s
      unarchive:
        src: https://.../k9s.tar.gz
        dest: /usr/local/bin
      when: devtools_features.k9s | default(false)
    ```

## Solução de Problemas

*   **Erro de Permissão:** O `make local` pedirá sua senha de `sudo`. Certifique-se de que seu usuário tem permissões de sudo.
*   **Falha em Pacotes:** Se um pacote não for encontrado, verifique se o arquivo em `roles/*/vars/` correspondente à sua distro contém o nome correto do pacote.
