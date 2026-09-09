# Loot Trinket + ServerHop

Use o mesmo `loader.lua` no AutoExecute do executor. Em **cada novo carregamento**,
o ciclo e **Farm → Full → Sell → Resume** são ativados, mesmo que o arquivo salvo
esteja desligado. Play só começa depois da checagem dos jogadores. STOP pausa a
sessão atual; o próximo carregamento volta a iniciar automaticamente.

O bot percorre **a rota inteira** e acompanha coletas confirmadas e detecções que passam pelos filtros de loot:

- Coletou ou detectou pelo menos um alvo, mesmo sem conseguir pegá-lo: começa outra volta completa no mesmo servidor.
- Terminou uma volta inteira sem coletar nada e sem detectar alvos: faz ServerHop.
- Sem rota salva ativa: coleta normalmente, mas não faz hop automático por falta
  de loot. Configure os pontos em **Botting → Trinket Route**.

Venda e retomada preservam a contagem da volta. Vender itens não diminui esse
contador. Não há hop automático por tempo ocioso nem por limite de permanência.
Os gatilhos de cargo relevante e o botão de hop manual continuam imediatos.

O grupo 36025827 é consultado para todos os jogadores e novas entradas. Tester,
money tester, Admin, Owner e ranks a partir de Tester pedem hop; Member é
ignorado. Consultas que falham mantêm o bot pausado; use **RETRY CHECK / HOP**.

AutoExecute e a fila de teleport compartilham uma trava por JobId para evitar
instâncias duplicadas. Quando o executor não oferece `queue_on_teleport`, o
AutoExecute precisa executar o loader após cada troca. Logs continuam em
`endHub-console.txt`, com prefixos `[EndHub Cycle]` e `[EndHub Role]`.

Verificação: `python tests/run_lua_tests.py` (biblioteca Lua 5.4) ou
`lua5.4 tests/server_cycle_test.lua`, executado na raiz do repositório. Os testes
usam serviços simulados; não substituem a validação dentro do Roblox.

## Entrada automática no jogo

Após verificar os jogadores, o ciclo procura os botões visíveis do jogo: **Play / Resistir**, **Slot 1** e **Current Server / Servidor atual**, conforme o menu enviado. Clica uma vez por tentativa, com intervalo de dois segundos. Só libera o Loot quando o menu desaparece e há personagem vivo. Não cria nem exclui slots. Se a interface mudar e não houver botão reconhecido, aguarda e mostra o status; os cliques aparecem em `[EndHub Menu]`.

## Morte e respawn

Coleta e venda ficam bloqueadas sem personagem vivo, durante a troca de personagem e por cinco segundos após o novo personagem estar disponível. O menu precisa fechar antes da retomada. Morrer cancela a venda pendente e descarta a posição de retorno do personagem anterior. Esta proteção não remove insanity de áreas do mapa.
