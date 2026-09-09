# Loot Trinket + ServerHop

Use o mesmo loader do EndHub na pasta **AutoExecute** do seu executor:

```lua
loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/3213123213fefefefe/endhub/main/loader.lua"
))()
```

O loader carrega o EndHub e seus ajustes atuais; instala o módulo de ciclo por
último; aguarda o jogo, Players e o personagem; verifica os jogadores; e libera
o Loot. A opção de ciclo vem ligada na primeira execução. O botão **STOP
CONTINUOUS CYCLE** salva a opção desligada, inclusive para o próximo servidor.
Use **START CONTINUOUS CYCLE** para reativar.

Quando `queue_on_teleport` ou uma variante compatível existe, o módulo também
enfileira esse loader uma única vez por servidor. AutoExecute e a fila podem
executá-lo juntos: uma trava global por `JobId` impede outra instância, mesmo
durante o carregamento. A fila cobre teleports; a primeira entrada no jogo
depende da configuração de AutoExecute do executor. Sem suporte à fila, manter
o loader no AutoExecute é necessário para continuar após o teleport.

## Checagem do grupo

Grupo: [BlackstarDW Studios, 36025827](https://www.roblox.com/communities/36025827/BlackstarDW-Studios#!/about).

| Cargo | Rank verificado | Comportamento |
| --- | ---: | --- |
| Guest / Member | 0 / 1 | Permite continuar |
| Tester | 252 | ServerHop |
| money tester | 253 | ServerHop |
| Admin | 254 | ServerHop |
| Owner | 255 | ServerHop |

Ranks consultados no [endpoint de cargos do grupo](https://groups.roblox.com/v1/groups/36025827/roles).
O módulo atualiza o limite do cargo Tester com `GetGroupInfoAsync` e também
reconhece os nomes, ignorando maiúsculas e espaços extras. Um cargo com rank
igual ou superior ao Tester também pede ServerHop; Member e Guest são ignorados.

Cada jogador, incluindo o jogador local, é consultado pelo `UserId`. A API
`GetRolesInGroupAsync` permite verificar todos os cargos; `GetGroupsAsync` é a
alternativa para clientes sem essa API. Há no máximo quatro verificações de
jogadores em andamento, com três tentativas e limite de espera por tentativa.
Uma consulta sem resposta válida mantém o Loot pausado; ela nunca significa
que o jogador foi aprovado. Use **RETRY CHECK / HOP** se as tentativas falharem.

Existe uma conexão de `PlayerAdded` para este monitor. Um novo jogador pausa
coleta e venda antes da consulta. Se for permitido, o processo retoma, mantendo
a posição de retorno de uma venda em andamento. Se for relevante, cancela o
trabalho e pede uma única troca de servidor. Sair do jogo ou parar o ciclo
invalida os resultados pendentes. Unload desconecta o monitor.

## Condições de troca

- Com uma rota salva ativa: depois do último ponto, da espera nesse ponto e da
  coleta dos trinkets correspondentes disponíveis, pede ServerHop.
- Sem rota ativa: pede ServerHop após 30 segundos sem loot correspondente
  disponível; ajuste em **Botting → Loot + ServerHop → Hop after no loot**.
- Um cargo relevante encontrado, ou **SERVERHOP NOW**, também pede a troca.
- Para outros gatilhos do EndHub, use `H.ServerHop.Request("motivo")` ou
  `H.ServerCycle.OnLootComplete()` ao concluir uma tarefa.

O período sem loot não conta durante a venda. Os filtros, rota salva, posição
do Clement e ajustes de venda continuam usando a persistência existente.
**Sell when full** controla a venda automática durante o ciclo.

A busca usa servidores públicos do mesmo PlaceId, pula servidores cheios e o
atual, e evita os visitados na última hora. Falhas de teleport tentam outros
servidores, com até três tentativas. Sem destino ou após falhas repetidas, o
ciclo fica pausado e mostra o motivo; **RETRY CHECK / HOP** refaz a verificação,
e **SERVERHOP NOW** pede outra troca. Parar o ciclo cancela novas tentativas,
mas não desfaz um teleport já aceito pelo Roblox.

Os logs `[EndHub Cycle]` e `[EndHub Role]` entram na captura existente em
`endHub-console.txt`. A consulta de cargos depende das APIs e do cache do
Roblox; não é uma garantia de detecção de mudanças de cargo durante a sessão.

## Verificação do código

```sh
lua5.4 tests/server_cycle_test.lua
# Alternativa em sistemas com a biblioteca compartilhada Lua 5.4:
python tests/run_lua_tests.py
```

Os testes usam serviços e relógio simulados. Cobrem as entradas reais de
carregamento, duplicações, cargos, chegadas/saídas, cancelamento de consultas,
retomada de vendas, fim da rota, persistência do ciclo e falhas de teleport.
Não executam Roblox nem confirmam teleports ou coleta em um servidor real.
