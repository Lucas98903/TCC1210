(********************************************************************
 * COPYRIGHT --
 ********************************************************************
 * PROGRAM: NewProgram
 * File: NewProgramCyclic.st
 * Author: Lucas e João Gabriel / adaptacao MQR + PI
 *
 * CONTROLE DE NIVEL COM:
 *   - leitura bruta em pressao (INT)
 *   - conversao pressao -> nivel em cm
 *   - MQR online
 *   - PI simples OU PI adaptativo
 *   - Start por EDGEPOS
 *   - Stop NC por EDGENEG
 *
 * IMPORTANTE SOBRE AS UNIDADES:
 *
 *   pressao     = leitura bruta DO ADC
 *   P_centimetro= nivel convertido para cm
 *   y           = nivel em cm usado pelo MQR e pelo PI
 *   percentual  = comando normalizado 0..100 %
 *   potencia    = comando bruto enviado ao inversor
 *
 * Para manter compatibilidade com o G2:
 *
 *      0 % -> 12000
 *    100 % -> 18000
 *
 * portanto:
 *
 *   potencia = 12000 + percentual*60
 *
 * O MQR usa u = percentual.
 *
 * Modelo:
 *
 *   y(k) = Theta[0]*y(k-1) + Theta[1]*u(k-1)
 *
 ********************************************************************)


PROGRAM _INIT

    (* ============================================================= *)
    (* 1. AQUISICAO / AMOSTRAGEM                                    *)
    (* ============================================================= *)

	Ts := 0.1;

	pressao_soma := 0.0;
	amostra_cont := 0;
	pressao_media := 0.0;


	(* ============================================================= *)
	(* 2. MODELO INICIAL G2                                         *)
	(* ============================================================= *)
	(*
	G2 identificado na regiao de 50 %:

	y(k) =
	0.998328836*y(k-1)
	+ 0.001311531*u(k-1)

	onde u esta em porcentagem.

	Aproximacao continua:

	0.784801
	G2(s) = -----------------
	59.789*s + 1
	*)

	Theta[0] := 0.998328836;
	Theta[1] := 0.001311531;

	P[0,0] := 1000.0;
	P[0,1] := 0.0;
	P[1,0] := 0.0;
	P[1,1] := 1000.0;

    (* Mantido coerente com os ensaios do TCC.
       Se houver muita oscilacao em malha fechada, testar 0.98/0.99. *)
	Lambda := 0.98;

	y_prev := 0.0;
	u_prev := 0.0;

	PrimeiraAmostra := TRUE;


	(* ============================================================= *)
	(* 3. START / STOP / MODO DE CONTROLE                           *)
	(* ============================================================= *)

	LIGA := FALSE;

	StartPulso := FALSE;
	StopPulso := FALSE;

    (* FALSE = PI simples com ganhos do G2
       TRUE  = PI adaptativo pelo MQR *)
	PI_Adaptativo := FALSE;


	(* ============================================================= *)
	(* 4. SUPERVISOR DE ESTABILIDADE DO MQR                         *)
	(* ============================================================= *)

	SomaTheta0_1s := 0.0;
	SomaTheta1_1s := 0.0;

	ContAmostras1s := 0;
	ContJanela := 0;

	MediaTheta0_1s := 0.0;
	MediaTheta1_1s := 0.0;

	Soma0 := 0.0;
	Soma1 := 0.0;
	SomaT0 := 0.0;
	SomaT1 := 0.0;

	SlopeTheta0 := 0.0;
	SlopeTheta1 := 0.0;

	(* Valores iniciais; ajustar experimentalmente depois *)
	EpsTheta0 := 0.060;
	EpsTheta1 := 0.006;

	ContEstavel := 0;
	EstavelNecessario := 2;

	ModeloEstavel := FALSE;
	ModeloValido := FALSE;
	ModeloAceito := FALSE;


	(* ============================================================= *)
	(* 5. MODELO CONTINUO INICIAL                                   *)
	(* ============================================================= *)

	GanhoPlanta := 0.784801;
	TauPlanta := 59.789;


	(* ============================================================= *)
	(* 6. PI INICIAL BASEADO NO G2                                  *)
	(* ============================================================= *)

	ZetaDesejado := 0.90;
	WnFactor := 1.20;

	Kp_Base := 1.4780817;
	Ti_Base := 48.16336;

	Kp_PI := Kp_Base;
	Ti_PI := Ti_Base;

	Kp_Alvo := Kp_Base;
	Ti_Alvo := Ti_Base;

	KpMin := 0.10;
	KpMax := 5.00;

	TiMin := 5.0;
	TiMax := 300.0;

	(* velocidade maxima de adaptacao *)
	KpRate := 2;       (* unidade de Kp / s *)
	TiRate := 5.00;       (* segundos de Ti / s *)


	(* ============================================================= *)
	(* 7. SETPOINT / PI                                              *)
	(* ============================================================= *)

	SP_Rampa := 0.0;

	(* rampa do setpoint em cm/s *)
	TaxaSP := 10;

	Erro_PI := 0.0;

	Integral_PI := 0.0;
	Integral_Candidato := 0.0;

	SaidaPI := 0.0;
	SaidaPI_SemLimite := 0.0;

	percentual := 0.0;
	potencia := 0;

	AtualizacoesPI := 0;



END_PROGRAM



PROGRAM _CYCLIC


    (* ============================================================= *)
    (* 0. LEITURA DA PLANTA: PRESSAO -> CM                          *)
    (* ============================================================= *)
    (*
       Mesma calibracao utilizada no codigo experimental anterior.
    *)

	P_centimetro :=
	(INT_TO_REAL(pressao) - 11492.51)
	/ 48.9164;

	P_psi :=
	INT_TO_REAL(pressao)
	* 0.0000336279
	- 0.226242;

	(* Variavel de processo do controle e do MQR *)
	y := P_centimetro;


	(* Media de P_psi a cada 10 amostras - somente diagnostico *)
	pressao_soma := pressao_soma + P_psi;
	amostra_cont := amostra_cont + 1;

	IF amostra_cont >= 10 THEN

		pressao_media := pressao_soma / 10.0;

		pressao_soma := 0.0;
		amostra_cont := 0;

	END_IF;



	(* ============================================================= *)
	(* 1. START E STOP                                               *)
	(* ============================================================= *)
	(*
	START:
	botao momentaneo.
	EDGEPOS(Start) arma LIGA.

	STOP:
	botao normalmente fechado.
	Normal:      Stop = TRUE
	Pressionado: Stop = FALSE

	EDGENEG(Stop) detecta TRUE -> FALSE.

	O teste NOT Stop permanece ativo para impedir religamento
	enquanto o circuito de STOP estiver aberto.
	*)

	StartPulso := EDGEPOS(Start);
	StopPulso := EDGENEG(Stop);


	(* STOP tem prioridade *)
	IF StopPulso OR (NOT Stop) THEN

		LIGA := FALSE;

		(* parada fisica do comando *)
		potencia := 0;

		percentual := 0.0;
		u := 0.0;

		Integral_PI := 0.0;
		Integral_Candidato := 0.0;

		SaidaPI := 0.0;
		SaidaPI_SemLimite := 0.0;

		Erro_PI := 0.0;

		PrimeiraAmostra := TRUE;

		ContAmostras1s := 0;
		ContJanela := 0;
		ContEstavel := 0;

		SomaTheta0_1s := 0.0;
		SomaTheta1_1s := 0.0;

		ModeloEstavel := FALSE;
		ModeloValido := FALSE;
		ModeloAceito := FALSE;

	END_IF;


	(* START somente com circuito de STOP fechado *)
	IF StartPulso AND Stop THEN

		LIGA := TRUE;

		(* Reinicia identificador no G2 em toda nova partida *)
		Theta[0] := 0.998328836;
		Theta[1] := 0.001311531;

		P[0,0] := 1000.0;
		P[0,1] := 0.0;
		P[1,0] := 0.0;
		P[1,1] := 1000.0;

		(* Toda partida comeca com PI base *)
		Kp_PI := Kp_Base;
		Ti_PI := Ti_Base;

		Kp_Alvo := Kp_Base;
		Ti_Alvo := Ti_Base;

		(* Comeca o setpoint interno no nivel atual *)
		SP_Rampa := y;

		Integral_PI := 0.0;

		percentual := 0.0;
		u := 0.0;

		PrimeiraAmostra := TRUE;

		ContAmostras1s := 0;
		ContJanela := 0;
		ContEstavel := 0;

		SomaTheta0_1s := 0.0;
		SomaTheta1_1s := 0.0;

		ModeloEstavel := FALSE;
		ModeloValido := FALSE;
		ModeloAceito := FALSE;

		AtualizacoesPI := 0;

	END_IF;



	(* ============================================================= *)
	(* 2. SISTEMA LIGADO                                            *)
	(* ============================================================= *)

	IF LIGA THEN


		(* ========================================================= *)
		(* 3. MQR                                                   *)
		(* ========================================================= *)
		(*
		IMPORTANTE:
		u = percentual.

		Nao usar o valor bruto "potencia" diretamente aqui,
		pois o G2 inicial foi identificado com a entrada em %.
		*)

		IF PrimeiraAmostra THEN

			y_prev := y;
			u_prev := percentual;

			PrimeiraAmostra := FALSE;

		ELSE


			(* ----------------------------------------------------- *)
			(* 3.1 Vetor de regressao                               *)
			(* ----------------------------------------------------- *)

			Phi[0] := y_prev;
			Phi[1] := u_prev;


			(* ----------------------------------------------------- *)
			(* 3.2 Predicao                                         *)
			(* ----------------------------------------------------- *)

			Y_hat :=
			Phi[0] * Theta[0]
			+ Phi[1] * Theta[1];


			(* ----------------------------------------------------- *)
			(* 3.3 Erro de identificacao                            *)
			(* ----------------------------------------------------- *)

			Error := y - Y_hat;


			(* ----------------------------------------------------- *)
			(* 3.4 Salva matriz P anterior                          *)
			(* ----------------------------------------------------- *)

			P00_old := P[0,0];
			P01_old := P[0,1];
			P10_old := P[1,0];
			P11_old := P[1,1];


			(* ----------------------------------------------------- *)
			(* 3.5 Denominador                                      *)
			(* ----------------------------------------------------- *)

			Den :=
			Lambda
			+ Phi[0] *
			(P00_old * Phi[0]
			+ P01_old * Phi[1])
			+ Phi[1] *
			(P10_old * Phi[0]
			+ P11_old * Phi[1]);


			IF ABS(Den) < 0.000000001 THEN

				IF Den >= 0.0 THEN
					Den := 0.000000001;
				ELSE
					Den := -0.000000001;
				END_IF;

			END_IF;


			(* ----------------------------------------------------- *)
			(* 3.6 Ganho do MQR                                     *)
			(* ----------------------------------------------------- *)

			K[0] :=
			(P00_old * Phi[0]
			+ P01_old * Phi[1])
			/ Den;

			K[1] :=
			(P10_old * Phi[0]
			+ P11_old * Phi[1])
			/ Den;


			(* ----------------------------------------------------- *)
			(* 3.7 Atualizacao de Theta                             *)
			(* ----------------------------------------------------- *)

			Theta[0] :=
			Theta[0]
			+ K[0] * Error;

			Theta[1] :=
			Theta[1]
			+ K[1] * Error;


			(* ----------------------------------------------------- *)
			(* 3.8 Atualizacao correta da matriz P                  *)
			(* ----------------------------------------------------- *)
			(*
			P(k) =
			[P(k-1) - K*Phi^T*P(k-1)] / Lambda
			*)

			P[0,0] :=
			(P00_old
			- K[0] *
			(Phi[0] * P00_old
			+ Phi[1] * P10_old))
			/ Lambda;

			P[0,1] :=
			(P01_old
			- K[0] *
			(Phi[0] * P01_old
			+ Phi[1] * P11_old))
			/ Lambda;

			P[1,0] :=
			(P10_old
			- K[1] *
			(Phi[0] * P00_old
			+ Phi[1] * P10_old))
			/ Lambda;

			P[1,1] :=
			(P11_old
			- K[1] *
			(Phi[0] * P01_old
			+ Phi[1] * P11_old))
			/ Lambda;



			(* ===================================================== *)
			(* 4. SUPERVISOR: MEDIA DE THETA A CADA 1 s            *)
			(* ===================================================== *)

			SomaTheta0_1s :=
			SomaTheta0_1s + Theta[0];

			SomaTheta1_1s :=
			SomaTheta1_1s + Theta[1];

			ContAmostras1s :=
			ContAmostras1s + 1;


			IF ContAmostras1s >= 10 THEN

				MediaTheta0_1s :=
				SomaTheta0_1s / 10.0;

				MediaTheta1_1s :=
				SomaTheta1_1s / 10.0;

				SomaTheta0_1s := 0.0;
				SomaTheta1_1s := 0.0;

				ContAmostras1s := 0;



				(* ================================================= *)
				(* 5. JANELA DAS ULTIMAS 10 MEDIAS = 10 s          *)
				(* ================================================= *)

				IF ContJanela < 10 THEN

					Theta0Janela[ContJanela] :=
					MediaTheta0_1s;

					Theta1Janela[ContJanela] :=
					MediaTheta1_1s;

					ContJanela :=
					ContJanela + 1;

				ELSE

					FOR i := 0 TO 8 DO

						Theta0Janela[i] :=
						Theta0Janela[i+1];

						Theta1Janela[i] :=
						Theta1Janela[i+1];

					END_FOR;

					Theta0Janela[9] :=
					MediaTheta0_1s;

					Theta1Janela[9] :=
					MediaTheta1_1s;

				END_IF;



				(* ================================================= *)
				(* 6. COEFICIENTE ANGULAR                           *)
				(* ================================================= *)

				IF ContJanela >= 10 THEN

					Soma0 := 0.0;
					Soma1 := 0.0;

					SomaT0 := 0.0;
					SomaT1 := 0.0;


					FOR i := 0 TO 9 DO

						Soma0 :=
						Soma0 + Theta0Janela[i];

						Soma1 :=
						Soma1 + Theta1Janela[i];

						SomaT0 :=
						SomaT0
						+ INT_TO_REAL(i)
						* Theta0Janela[i];

						SomaT1 :=
						SomaT1
						+ INT_TO_REAL(i)
						* Theta1Janela[i];

					END_FOR;


                    (* para t = 0...9:
                       soma(t)   = 45
                       soma(t^2) = 285

                       denominador:
                       10*285 - 45^2 = 825
                    *)

					SlopeTheta0 :=
					(10.0 * SomaT0
					- 45.0 * Soma0)
					/ 825.0;

					SlopeTheta1 :=
					(10.0 * SomaT1
					- 45.0 * Soma1)
					/ 825.0;


					ThetaAceito[0] :=
					Soma0 / 10.0;

					ThetaAceito[1] :=
					Soma1 / 10.0;



					(* ================================================= *)
					(* 7. TESTE DE ESTABILIDADE                         *)
					(* ================================================= *)

					ModeloEstavel :=
					(ABS(SlopeTheta0)
					< EpsTheta0)
					AND
						(ABS(SlopeTheta1)
					< EpsTheta1);



					(* ================================================= *)
					(* 8. VALIDACAO DO MODELO                            *)
					(* ================================================= *)

					ModeloValido := FALSE;


					IF (ThetaAceito[0] > 0.0)
						AND
						(ThetaAceito[0] < 0.99999)
						AND
						(ThetaAceito[1] > 0.0) THEN


						GanhoPlanta :=
						ThetaAceito[1]
						/
						(1.0 - ThetaAceito[0]);


						TauPlanta :=
						-Ts
						/
						LN(ThetaAceito[0]);


						(* limites iniciais de plausibilidade *)
						IF (GanhoPlanta > 0.05)
							AND
							(GanhoPlanta < 5.0)
							AND
							(TauPlanta > 2.0)
							AND
							(TauPlanta < 250.0) THEN

							ModeloValido := TRUE;

						END_IF;

					END_IF;



					(* ================================================= *)
					(* 9. CONFIRMACAO POR VARIAS JANELAS                *)
					(* ================================================= *)

					IF ModeloEstavel
						AND ModeloValido THEN

						ContEstavel :=
						ContEstavel + 1;

					ELSE

						ContEstavel := 0;
						ModeloAceito := FALSE;

					END_IF;


					IF ContEstavel
						>= EstavelNecessario THEN

						ModeloAceito := TRUE;


						(* ============================================= *)
						(* 10. RECALCULO DO PI SOMENTE NO MODO          *)
						(*     ADAPTATIVO                                *)
						(* ============================================= *)

						IF PI_Adaptativo THEN

							Wn :=
							WnFactor
							/
							TauPlanta;


							Kp_Alvo :=
							(2.0
							* ZetaDesejado
							* Wn
							* TauPlanta
							- 1.0)
							/
							GanhoPlanta;


							Ti_Alvo :=
							(GanhoPlanta
							* Kp_Alvo)
							/
								(TauPlanta
							* Wn
							* Wn);


							(* limites Kp *)
							IF Kp_Alvo > KpMax THEN
								Kp_Alvo := KpMax;
							END_IF;

							IF Kp_Alvo < KpMin THEN
								Kp_Alvo := KpMin;
							END_IF;


							(* limites Ti *)
							IF Ti_Alvo > TiMax THEN
								Ti_Alvo := TiMax;
							END_IF;

							IF Ti_Alvo < TiMin THEN
								Ti_Alvo := TiMin;
							END_IF;


							AtualizacoesPI :=
							AtualizacoesPI + 1;

						END_IF;

					END_IF;

				END_IF;

			END_IF;

		END_IF;



		(* ========================================================= *)
		(* 11. ESCOLHA PI SIMPLES / PI ADAPTATIVO                   *)
		(* ========================================================= *)

		IF NOT PI_Adaptativo THEN

			(* PI simples sempre retorna aos ganhos do G2 *)
			Kp_Alvo := Kp_Base;
			Ti_Alvo := Ti_Base;

		END_IF;



		(* ========================================================= *)
		(* 12. ALTERACAO SUAVE DOS GANHOS                           *)
		(* ========================================================= *)
		(*
		PI simples:
		leva Kp/Ti suavemente de volta aos valores base.

		PI adaptativo:
		somente altera quando ModeloAceito = TRUE.
		*)

		IF (NOT PI_Adaptativo)
			OR
			(PI_Adaptativo AND ModeloAceito) THEN


			(* ---------------- Kp ---------------- *)

			DeltaMax :=
			KpRate * Ts;


			IF (Kp_Alvo - Kp_PI)
				> DeltaMax THEN

				Kp_PI :=
				Kp_PI + DeltaMax;

			ELSIF (Kp_Alvo - Kp_PI)
				< -DeltaMax THEN

				Kp_PI :=
				Kp_PI - DeltaMax;

			ELSE

				Kp_PI := Kp_Alvo;

			END_IF;


			(* ---------------- Ti ---------------- *)

			DeltaMax :=
			TiRate * Ts;


			IF (Ti_Alvo - Ti_PI)
				> DeltaMax THEN

				Ti_PI :=
				Ti_PI + DeltaMax;

			ELSIF (Ti_Alvo - Ti_PI)
				< -DeltaMax THEN

				Ti_PI :=
				Ti_PI - DeltaMax;

			ELSE

				Ti_PI := Ti_Alvo;

			END_IF;

		END_IF;



		(* ========================================================= *)
		(* 13. RAMPA DO SETPOINT                                    *)
		(* ========================================================= *)

		DeltaMax :=
		TaxaSP * Ts;


		IF (SP - SP_Rampa)
			> DeltaMax THEN

			SP_Rampa :=
			SP_Rampa + DeltaMax;

		ELSIF (SP - SP_Rampa)
			< -DeltaMax THEN

			SP_Rampa :=
			SP_Rampa - DeltaMax;

		ELSE

			SP_Rampa := SP;

		END_IF;



		(* ========================================================= *)
		(* 14. CONTROLADOR PI                                       *)
		(* ========================================================= *)

		Erro_PI :=
		SP_Rampa - y;


		IF Ti_PI < TiMin THEN
			Ti_PI := TiMin;
		END_IF;


		Integral_Candidato :=
		Integral_PI
		+ (Kp_PI / Ti_PI)
		* Erro_PI
		* Ts;


		SaidaPI_SemLimite :=
		Kp_PI * Erro_PI
		+ Integral_Candidato;



		(* ========================================================= *)
		(* 15. SATURACAO + ANTI-WINDUP                              *)
		(* ========================================================= *)

		IF SaidaPI_SemLimite > 100.0 THEN

			percentual := 100.0;

            (* permite integrar apenas se o erro tirar
               o controlador da saturacao superior *)
			IF Erro_PI < 0.0 THEN

				Integral_PI :=
				Integral_Candidato;

			END_IF;


		ELSIF SaidaPI_SemLimite < 0.0 THEN

			percentual := 0.0;

            (* permite integrar apenas se o erro tirar
               o controlador da saturacao inferior *)
			IF Erro_PI > 0.0 THEN

				Integral_PI :=
				Integral_Candidato;

			END_IF;


		ELSE

			percentual :=
			SaidaPI_SemLimite;

			Integral_PI :=
			Integral_Candidato;

		END_IF;


		SaidaPI := percentual;



		(* ========================================================= *)
		(* 16. % -> COMANDO BRUTO DO INVERSOR                       *)
		(* ========================================================= *)
		(*
		percentual = 0   -> potencia = 12000
		percentual = 50  -> potencia = 15000
		percentual = 100 -> potencia = 18000
		*)

		potencia := REAL_TO_INT(percentual * 320.0);


		(* Protecao adicional da faixa de controle *)
		IF potencia > 32000 THEN
			potencia := 32000;
		END_IF;

		IF potencia < 1000 THEN
			potencia := 1000;
		END_IF;


		(* entrada efetivamente usada pelo MQR *)
		u := percentual;



		(* ========================================================= *)
		(* 17. AMOSTRAS PARA O PROXIMO CICLO                        *)
		(* ========================================================= *)

		y_prev := y;
		u_prev := u;


	ELSE


		(* ========================================================= *)
		(* 18. SISTEMA PARADO                                       *)
		(* ========================================================= *)

		potencia := 0;

		percentual := 0.0;
		u := 0.0;

		SaidaPI := 0.0;

		Integral_PI := 0.0;
		Integral_Candidato := 0.0;

		SP_Rampa := y;

		PrimeiraAmostra := TRUE;

		ContEstavel := 0;

		ModeloAceito := FALSE;

	END_IF;

END_PROGRAM
