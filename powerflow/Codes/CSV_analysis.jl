using Printf
print("\033c")

function calcular_metricas()
    println(">> Lendo arquivos CSV e calculando métricas...\n")

    # 1. Tensão Mínima e Máxima (resultados_barras.csv)
    v_min = Inf
    v_max = -Inf
    for line in readlines("resultados_barras_SIN.csv")[2:end]
        parts = split(line, ",")
        v = parse(Float64, parts[3])
        
        # Ignora a tensão se for NaN
        if !isnan(v)
            v_min = min(v_min, v)
            v_max = max(v_max, v)
        end
    end

    # 2. Geração Ativa e Reativa (resultados_geracao.csv)
    p_gen_total = 0.0
    q_gen_total = 0.0
    for line in readlines("resultados_fluxos_linhas_SIN.csv")[2:end]
        parts = split(line, ",")
        p_val = parse(Float64, parts[3])
        q_val = parse(Float64, parts[4])
        
        # Só soma se NÃO for NaN
        if !isnan(p_val)
            p_gen_total += p_val
        end
        if !isnan(q_val)
            q_gen_total += q_val
        end
    end

    # 3. Perdas Ativas Totais (resultados_linhas.csv)
    p_loss_total = 0.0
    for line in readlines("resultados_fluxos_linhas_SIN.csv")[2:end]
        parts = split(line, ",")
        
        p_origem = parse(Float64, parts[4])
        p_destino = parse(Float64, parts[6])
        
        if !isnan(p_origem) && !isnan(p_destino)
            p_loss_total += (p_origem + p_destino)
        end
    end

    # Imprime a tabela de resultados formatada
    println("--- Resumo Global do Sistema ---")
    @printf("Tensão Mínima (pu)        : %.3f\n", v_min)
    @printf("Tensão Máxima (pu)        : %.3f\n", v_max)
    @printf("Perdas Ativas (Total pu)  : %.2f\n", p_loss_total)
    @printf("Geração Ativa Total (pu)  : %.2f\n", p_gen_total)
    @printf("Geração Reativa Total (pu): %.2f\n", q_gen_total)
    println("--------------------------------")
end

# Executa a função
calcular_metricas()