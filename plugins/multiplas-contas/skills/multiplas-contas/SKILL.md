---
name: multiplas-contas
description: Instala e mantém várias contas do Claude Code no Windows (uma principal e quantas secundárias quiser), alternadas com `cc <conta>` sem relogar (CLAUDE_CONFIG_DIR por conta, resto compartilhado com ~/.claude), mais o atalho "cc" na barra de endereço do Explorer. Use para instalar num PC novo, adicionar/remover conta secundária, trocar a conta principal, reinstalar depois de atualizar o plugin, desfazer, diagnosticar o `cc`, ou abrir uma sessão de outra conta (ex.: a principal, para publicar um artefato).
---

# Múltiplas contas do Claude Code (Windows)

O usuário tem **uma conta principal** e **quantas contas secundárias quiser**:
- A principal é a padrão do `cc` e onde os artefatos são publicados, salvo indicação explícita do usuário (com confirmação).
- As secundárias usam o mesmo ambiente e só mudam o login, por exemplo para ter mais cota.
- Os nomes das contas são escolhidos pelo usuário. Não presuma nomes nem quantidade.

Os scripts ficam na pasta `scripts/` ao lado deste SKILL.md e são instalados em `~/.claude-contas`. Rode-os sempre com `powershell -NoProfile -ExecutionPolicy Bypass -File <script>`: a política de execução padrão do Windows bloqueia .ps1.

## Como funciona (para explicar ao usuário)
- Cada conta tem uma pasta de config própria (`CLAUDE_CONFIG_DIR`) com seu login (`.credentials.json`) e seu `.claude.json`.
- Todo o resto aponta para `~/.claude` (a "pasta mestre"): `settings.json`, `history.jsonl`, `CLAUDE.md`, `keybindings.json` por link de arquivo; `projects/`, `skills/`, `plugins/`, `sessions/` etc. por junction. Assim, histórico, memória, skills, plugins e a lista de sessões são iguais em todas as contas.
- A conta já logada em `~/.claude` usa a própria pasta mestre (`"pasta": "~/.claude"`) e roda **sem** `CLAUDE_CONFIG_DIR`.
- `cc [conta] [args]` abre o Claude na conta (sem conta = padrão), confere o e-mail logado com `claude auth status --json` e nomeia a sessão "pasta (conta)". `cc -l` lista as contas, se o RC liga por padrão em cada uma e o uso de cada uma (janela de 5h e semanal).
- **Remote Control por conta:** o `settings.json` é compartilhado, então o `cc` decide o RC de cada sessão passando `--settings ~/.claude-contas/rc/ligado.json` ou `desligado.json`. Liga só nas contas com `"rc": true` no `contas.json`; `cc <conta> --rc [nome]` liga e `--no-rc` desliga, só naquela sessão. O `settings.json` compartilhado fica com `remoteControlAtStartup: false` (gravado pelo `setup-contas.ps1` e conferido a cada `cc`), para que sessões abertas sem o `cc` (claude direto, IDE, app) não liguem o RC.
- **Uso:** o `cc` consulta `api.anthropic.com/api/oauth/usage` com o token lido, só em memória, do `.credentials.json` da própria conta. Se o token venceu (ele só é renovado quando a conta roda), mostra o último uso que a conta salvou no `.claude.json`, com o horário. Ao abrir uma conta com uso igual ou acima de `avisoUso` (padrão 80) na janela de 5h ou na semanal, o `cc` avisa, sugere a conta com mais folga e pergunta antes de abrir (no modo `-p`, só avisa em stderr).
- **Status line:** `statusline.ps1` mostra `<conta> · Sessão (5h): x% · Semana: y%`, em amarelo a partir de `avisoUso` e em vermelho a partir de 95%. O `setup-contas.ps1` registra no `settings.json` só se não houver outra status line.
- Na barra de endereço do Explorer, o atalho (padrão `cc`) abre o PowerShell na pasta atual com `cc`. O Explorer não repassa a pasta para comandos do App Paths, então `explorer/claude-aqui.ps1` descobre a pasta pela janela do Explorer que está na frente.
- Uma conta nova recebe só as chaves de configuração do `~/.claude.json` (MCPs, projetos confiáveis etc.), nunca os dados da conta. Conectores do claude.ai são por conta e se configuram no site.

## Instalar num PC novo
1. Rode `scripts/instalar.ps1 -Verificar`. Ele mostra o caminho do `claude.exe`, se há symlink (modo desenvolvedor) e conflitos. Se houver PROBLEMA, resolva com o usuário antes de seguir.
2. Rode `claude auth status --json` (sem `CLAUDE_CONFIG_DIR`) para saber qual e-mail já está logado em `~/.claude`.
3. Pergunte ao usuário, de uma vez:
   - nome curto e e-mail da **conta principal**;
   - nome curto e e-mail de cada **secundária**, quantas forem;
   - em qual conta a extensão Claude in Chrome está logada, se o usuário usa a extensão (campo `chrome`; o Claude Code não consegue detectar isso sozinho);
   - o atalho do Explorer (padrão `cc`).
   - em quais contas o Remote Control deve ligar por padrão (campo `"rc": true`; sem ele, o RC fica desligado). Contas de trabalho geralmente ficam desligadas.
   O caso comum é a principal já estar logada em `~/.claude` (passo 2) e as secundárias serem adicionadas depois.
   - **Só uma conta tem `"pasta": "~/.claude"`:** a que está logada lá. As outras ficam em `~/.claude-contas/<nome>` sem precisar do campo. Se nenhuma conta tiver `pasta`, a principal usa `~/.claude`.
   - Se o e-mail logado em `~/.claude` for o de uma secundária, é ela que recebe `"pasta": "~/.claude"`, e a principal ganha pasta própria (com um `/login`). Explique isso ao usuário.
   - Não copie `.credentials.json` de uma pasta para outra.
4. Escreva `~/.claude-contas/contas.json` em UTF-8 sem BOM, no formato de `scripts/contas.exemplo.json`, com `"principal": "<nome>"`. Se o usuário quiser que o `cc` sem argumento abra outra conta, acrescente `"padrao": "<nome>"`; a principal continua sendo a única que publica.
5. Rode `scripts/instalar.ps1`. Ele faz backup na primeira vez, copia os scripts, cria as pastas e os links, põe `~/.claude-contas/bin` no PATH, registra o atalho do Explorer e escreve o bloco de contas no `~/.claude/CLAUDE.md` (entre marcas `<!-- multiplas-contas:... -->`, preservando o resto do arquivo).
6. Passe ao usuário os próximos passos:
   - abrir um terminal **novo** (o PATH mudou);
   - rodar `cc <conta>` e `/login` uma vez em cada conta não logada;
   - conferir com `cc -l`.

## Manutenção
- **Adicionar conta secundária:** acrescente a conta em `~/.claude-contas/contas.json` e rode `~/.claude-contas/setup-contas.ps1`, que é idempotente e também atualiza o CLAUDE.md. Depois o usuário roda `cc <nova>` e faz `/login`.
- **Mudar o RC padrão de uma conta ou o limite do aviso de uso:** edite `"rc"` da conta ou `"avisoUso"` no `contas.json`. Vale no próximo `cc`.
- **Trocar a principal, o padrão, a conta do Chrome ou o atalho:** edite `contas.json` e rode `setup-contas.ps1`. Se mudou o atalho, rode `instalar.ps1`, que registra o novo; apague à mão a chave antiga em `HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\<antigo>.exe`.
- **Remover uma conta:** primeiro tire os links da pasta dela com `. ~/.claude-contas/comum.ps1; Remove-LinksConta ((Get-Contas).Contas | ? Nome -eq '<conta>')`. Confira que não sobrou link na pasta (`Get-ChildItem -Force | ? LinkType`). Só então apague a pasta, tire a conta do `contas.json` e rode `setup-contas.ps1`.
- **Depois de atualizar o plugin:** rode `scripts/instalar.ps1` de novo para copiar os scripts novos. Ele não refaz o backup nem toca no `contas.json`.
- **Desfazer:** `~/.claude-contas/desfazer-contas.ps1` remove links, PATH, atalho e o bloco do CLAUDE.md. Com `-ApagarPastas`, apaga também as pastas das contas extras.

## Publicar artefato em outra conta
- **Conta alvo:** a principal, se o usuário não indicou nenhuma. Se ele indicou outra, confirme antes com AskUserQuestion, mostrando nome e e-mail ("Publicar na conta X (email), não na principal?"). Só siga com um sim. Nunca troque a conta alvo por conta própria.
1. Confira a conta da sessão atual com `claude auth status --json`. Se já for a conta alvo, publique aqui.
2. Senão, grave o conteúdo num arquivo e procure com ListAgents uma sessão cujo nome termine em "(<conta alvo>)".
3. Se não houver, rode `~/.claude-contas/abrir-conta.ps1 <conta alvo> <pasta>`, que abre uma janela nova, e procure a sessão de novo.
4. Peça por SendMessage que ela confira a própria conta com `claude auth status --json` e publique o arquivo.
5. O `cc` tira as variáveis `CLAUDE*` herdadas desta sessão (menos `CLAUDE_CONFIG_DIR`); sem isso, a janela nova abriria com "Transcript saving is off" e não apareceria no ListAgents.
6. O modo automático dela pede a aprovação do usuário na janela dela. Isso é esperado; avise o usuário.

Claude in Chrome não precisa disso: funciona a partir de qualquer conta. O campo `chrome` do `contas.json` só registra em qual conta a extensão está logada (aparece no `cc -l` e no CLAUDE.md).

## Nunca
- `Remove-Item -Recurse` (ou apagar pelo Explorer) numa pasta de conta que ainda tem junctions. Isso apaga o conteúdo real de `~/.claude`. Use `Remove-LinksConta` ou `desfazer-contas.ps1`.
- Copiar ou mover `.credentials.json` entre pastas: o token é renovado e a cópia deixa de valer.
- Definir `CLAUDE_CONFIG_DIR` apontando para `~/.claude`: o Claude passaria a procurar `.claude.json` dentro da pasta.
- Usar `$PROFILE` para o `cc`: em PCs com a política de execução padrão, ele não carrega. O `cc` é um `.cmd` no PATH de propósito.

## Diagnóstico
- **Digitar o atalho no Explorer abre uma pasta em vez do Claude:** existe uma pasta com esse nome (o Explorer navega antes de executar). Troque `atalhoExplorer`. `instalar.ps1 -Verificar` procura esses conflitos.
- **Atalho do Explorer dá "Não é possível localizar o tipo [W.U]":** o `Add-Type` falhou porque `TMP` aponta para `C:\Windows\TEMP` (falta `TMP` no ambiente do usuário). Desde a 1.3.1 o `claude-aqui.ps1` corrige isso na própria sessão; se ainda acontecer, reinstale os scripts. Para corrigir no Windows, crie `TMP` do usuário igual ao `TEMP` (`%USERPROFILE%\AppData\Local\Temp`).
- **"cc não é reconhecido":** o terminal foi aberto antes da instalação. Abra outro.
- **Aviso "logada como X, esperado Y":** o `/login` foi feito com o e-mail errado naquela pasta. Rode `/logout` e `/login` dentro de `cc <conta>`.
- **Mensagem "alteração levada para a mestre":** um programa salvou por cima de um link e o `cc` refez o link. O conteúdo anterior fica em `~/.claude-contas/backups`.
- **Uso aparece como "(salvo HH:mm)":** o token daquela conta venceu, então o valor é o último que ela salvou. Abrir a conta com `cc <conta>` atualiza. O `cc` não renova o token sozinho de propósito.
- **Status line de conta e uso não aparece:** o `settings.json` já tinha outra `statusLine`, e o instalador não mexe nela. Para usar a nossa, tire a outra e rode `setup-contas.ps1`.
- **RC ligou numa conta sem `rc`:** confira se alguém pôs `remoteControlAtStartup: true` no `settings.json` compartilhado (o `cc` volta para `false` ao abrir) ou se a sessão foi aberta com `--rc`.
