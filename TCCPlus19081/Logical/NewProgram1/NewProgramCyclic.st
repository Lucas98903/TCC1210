(********************************************************************
 * COPYRIGHT --
 ********************************************************************
 * PROGRAM: NewProgram
 * File: NewProgramCyclic_Proposto2.st
 * Author: Lucas e João Gabriel / adaptacao MQR + PI (versao proposta 2)
 *
 * Versao proposta para comparar em bancada com o codigo anterior
 * (NewProgramCyclicOLD.txt). Mesmas entradas e saidas: pressao,
 * Start, Stop, SP, PI_Adaptativo -> potencia.
 * Usar junto com NewProgram_Proposto2.var.
 *
 * A saida continua como no codigo anterior: potencia = 320*%
 * (1000..32000). A proposta 1 tinha voltado para 12000 + 60*% e
 * ficou ~3x mais lenta na bancada (ensaios de 12/10/2026).
 *
 * MUDANCAS EM RELACAO AO CODIGO ANTERIOR:
 *
 *   [1] MQR a cada 5 s (Ts_Id), sobre a media de 50 amostras de y e u.
 *       Com Ts = 0,1 s, Theta[0] fica em 0,998, tao perto de 1 que o
 *       ruido do nivel leva o tau estimado para ~5 s (real ~60 s).
 *       Com 1 s ainda sobra vies: na simulacao com o modelo ajustado
 *       aos traces de 12/10/2026, as ondas do nivel (3 a 7 s) e o
 *       atraso da bomba (~1,3 s) puxam o tau estimado para ~metade.
 *       Com 5 s, Theta[0] ~ 0,92 e o tau estimado fica a ~20 % do
 *       tau local na mesma simulacao.
 *
 *   [2] Modelo com termo constante:
 *          y(k) = Theta[0]*y(k-1) + Theta[1]*u(k-1) + Theta[2]
 *       K = Theta[1]/(1 - Theta[0]) passa a ser o ganho local
 *       (incremental), e nao a razao nivel/comando.
 *
 *   [3] Lambda = 0,95 (memoria de 20 amostras = 100 s) e limite do
 *       traco de P.
 *
 *   [4] MQR congelado fora da faixa util da bomba: u <= U_ZonaMorta
 *       (41 %, a bomba nao vence a coluna) ou u >= U_MaxId (75 %,
 *       acima disso a vazao quase nao aumenta). Nesses trechos o
 *       modelo linear nao vale.
 *
 *   [5] Supervisor aplicado a K e tau: faixa fisica (K 2,5..30 cm/%,
 *       tau 20..200 s) e variacao relativa na janela das ultimas 10
 *       estimativas (50 s).
 *       K e tau aceitos passam por um filtro de 1a ordem.
 *
 *   [6] Sintonia: mesma regra de alocacao de polos, com
 *       ZetaDesejado = 2,0 e WnFactor = 2 + raiz(3) = 3,732. Com esses
 *       valores a regra da Ti = tau: o zero do PI cancela o polo da
 *       planta e o outro polo fica em -13,93/tau (constante de tempo
 *       de malha fechada ~ tau/13,9, ~4,3 s com tau = 60 s).
 *       Kp 0,5..3,0, Ti 30..150 s, KpRate 0,02/s, TiRate 1 s/s e
 *       medicao filtrada (0,5 s) no PI.
 *
 *   [7] Modelo inicial definido por K_Ini e Tau_Ini (G2 convertido
 *       para a escala 320*%) e reaplicado a cada START (Theta, P e PI
 *       base). Para partir de um modelo errado de proposito, basta
 *       mudar K_Ini/Tau_Ini no Watch antes do START.
 *
 *   [8] MQR atualizado somente ate T_Excitacao = 120 s (~2 tau) depois
 *       de cada mudanca de SP (ou START). Com o SP parado, so o ruido
 *       excita o MQR e Theta[0] deriva para baixo.
 *
 *   [9] Integral pre-carregada com U_Partida = 42 % no START, logo
 *       acima da zona morta da bomba. Partindo de 0 %, a integral
 *       levava ~90 s para chegar aos ~50 % que seguram o nivel.
 *
 * Mantidos iguais: calibracao do nivel, START/STOP, sequencia de
 * degraus no SP, rampa do SP (TaxaSP) e anti-windup do PI.
 ********************************************************************)


PROGRAM _INIT

	(* ============================================================= *)
	(* 1. AQUISICAO / AMOSTRAGEM                                    *)
	(* ============================================================= *)

	Ts := 0.1;			(* ciclo do PI (Cyclic#4) *)
	Ts_Id := 5.0;		(* [1] amostragem do MQR = 50 ciclos *)

	pressao_soma := 0.0;
	amostra_cont := 0;
	pressao_media := 0.0;

	SomaY_Id := 0.0;
	SomaU_Id := 0.0;
	ContId := 0;
	ContSatId := 0;


	(* ============================================================= *)
	(* 2. MODELO INICIAL E MQR                                      *)
	(* ============================================================= *)
	(*
	[7] Modelo inicial, aplicado na secao 2 do ciclico:

	G2: tau = 59,789 s.
	[2] Ganho LOCAL inicial: 1,65 cm/% na escala do ensaio do G2
	(12000 + 60*%), medido nas transicoes 33 <-> 50 %, e nao 0,785
	(razao nivel/comando). Na escala 320*% da saida:
	1,65 * 320/60 = 8,8 cm/%.

	Com Ts_Id = 5 s:
	Theta[0] = EXP(-Ts_Id/Tau_Ini)  = 0.919763
	Theta[1] = K_Ini*(1 - Theta[0]) = 0.706086
	Theta[2] e calculado na 1a amostra, para que a predicao inicial
	coincida com a medida.
	*)

	K_Ini := 8.8;			(* cm/% na escala 320*% *)
	Tau_Ini := 59.789;		(* s *)

	(* [3] P inicial pequena em Theta[0] e Theta[1] (confia no modelo
	inicial) e grande no termo constante (desconhecido) *)
	P0_Diag[0] := 0.0025;	(* 0,0001*5^2: mesma confianca da proposta 1 *)
	P0_Diag[1] := 0.75;		(* 0,001*(320/60)^2*5^2 *)
	P0_Diag[2] := 10.0;

	(* [3] memoria efetiva 1/(1-Lambda) = 20 amostras = 100 s *)
	Lambda := 0.95;

	(* [4] faixa util da bomba para o MQR (traces de 12/10/2026):
	abaixo de ~13100 contagens a bomba nao vence a coluna e acima de
	~24000 a vazao quase nao aumenta *)
	U_ZonaMorta := 41.0;	(* % = 13120 contagens *)
	U_MaxId := 75.0;		(* % = 24000 contagens *)

	(* [8] tempo de identificacao depois de cada mudanca de SP *)
	T_Excitacao := 120.0;	(* s *)
	TempoSemSP := 0.0;
	SP_Anterior := 0.0;

	y_prev := 0.0;
	u_prev := 0.0;

	PrimeiraAmostra := TRUE;
	OffsetIniciado := FALSE;

	(* Theta, P e PI base sao calculados na secao 2 do ciclico *)
	ReiniciaModelo := TRUE;


	(* ============================================================= *)
	(* 3. START / STOP / MODO DE CONTROLE                           *)
	(* ============================================================= *)

	LIGA := FALSE;

	StartPulso := FALSE;
	StopPulso := FALSE;

	(* FALSE = PI simples com os ganhos do modelo inicial
	   TRUE  = PI adaptativo pelo MQR *)
	PI_Adaptativo := FALSE;


	(* ============================================================= *)
	(* 4. SUPERVISOR DO MQR                                          *)
	(* ============================================================= *)

	ContJanela := 0;

	(* [5] variacao maxima admitida na janela das ultimas 10
	estimativas (50 s), relativa a media da janela *)
	VarRelMaxK := 0.10;
	VarRelMaxTau := 0.15;

	(* [5] faixa fisica da planta, com folga (ganho local estimado
	dos traces de 12/10/2026: ~8 cm/% em 22 cm e ~12 cm/% em 67 cm,
	na escala 320*%; tau do G2: 60 s) *)
	GanhoMinPl := 2.5;
	GanhoMaxPl := 30.0;
	TauMinPl := 20.0;
	TauMaxPl := 200.0;

	(* [5] filtro de 1a ordem dos parametros aceitos
	(constante de tempo ~ Ts_Id/AlfaParam) *)
	AlfaParam := 0.3;

	ContEstavel := 0;
	EstavelNecessario := 5;

	ModeloEstavel := FALSE;
	ModeloValido := FALSE;
	ModeloAceito := FALSE;


	(* ============================================================= *)
	(* 5. SINTONIA DO PI                                             *)
	(* ============================================================= *)
	(*
	Alocacao de polos, mesma regra no PI base e no adaptativo:

	Wn = WnFactor/tau
	Kp = (2*zeta*WnFactor - 1)/K
	Ti = (2*zeta*WnFactor - 1)*tau/WnFactor^2

	[6] Com ZetaDesejado = 2 e WnFactor = 2 + raiz(3):
	2*zeta*WnFactor - 1 = WnFactor^2 = 13,93, logo Ti = tau e
	Kp = 13,93/K. Os polos de malha fechada ficam em -1/tau (cancelado
	pelo zero do PI) e -13,93/tau.

	Com K_Ini = 8,8 e Tau_Ini = 59,789: Kp = 1,5828 e Ti = 59,79 s.
	(Codigo anterior: Kp = 1,4781 e Ti = 48,16 s.)
	*)

	ZetaDesejado := 2.00;	(* [6] antes 0.90 *)
	WnFactor := 3.732;		(* [6] antes 1.20 *)

	KpMin := 0.50;			(* [6] antes 0.10 *)
	KpMax := 3.00;			(* [6] antes 5.00 *)

	TiMin := 30.0;			(* [6] antes 5.0 *)
	TiMax := 150.0;			(* [6] antes 300.0 *)

	(* [6] velocidade maxima de adaptacao *)
	KpRate := 0.02;			(* unidade de Kp / s (antes 2) *)
	TiRate := 1.00;			(* segundos de Ti / s (antes 5) *)


	(* ============================================================= *)
	(* 6. SETPOINT / PI                                              *)
	(* ============================================================= *)

	SP_Rampa := 0.0;

	(* rampa do setpoint em cm/s. Mesmo valor do codigo anterior,
	para comparar os dois com o mesmo perfil de SP *)
	TaxaSP := 10.0;

	(* [6] filtro de 1a ordem da medicao usada pelo PI *)
	TfMedicao := 0.5;		(* s *)
	y_f := 0.0;

	(* [9] valor da integral no START: logo acima da zona morta *)
	U_Partida := 42.0;		(* % = 13440 contagens *)

	Erro_PI := 0.0;

	Integral_PI := 0.0;
	Integral_Candidato := 0.0;

	SaidaPI := 0.0;
	SaidaPI_SemLimite := 0.0;

	percentual := 0.0;
	potencia := 0;

	AtualizacoesPI := 0;


	(* ============================================================= *)
	(* 7. SEQUENCIA DE DEGRAUS NO SETPOINT                          *)
	(* ============================================================= *)
	(*
	EnsaioDegraus = TRUE:
	a cada START o programa escreve em SP a sequencia de degraus
	abaixo, um a cada Degrau_Tempo segundos, com o PI em malha
	fechada. Ao fim do ultimo degrau o SP permanece no ultimo
	valor e Degrau_Concluido = TRUE.

	EnsaioDegraus = FALSE:
	SP fica livre para ser alterado pelo operador.

	Degrau_Valor em cm. Maximo de 10 degraus.
	*)

	EnsaioDegraus := TRUE;

	(* duracao de cada degrau em segundos *)
	Degrau_Tempo := 60.0;

	Degrau_N := 6;

	Degrau_Valor[0] := 33.33;
	Degrau_Valor[1] := 50.00;
	Degrau_Valor[2] := 33.33;
	Degrau_Valor[3] := 66.67;
	Degrau_Valor[4] := 22.08;
	Degrau_Valor[5] := 41.67;

	Degrau_Ativo := FALSE;
	Degrau_Concluido := FALSE;
	Degrau_Etapa := 0;
	Degrau_Cnt := 0;

END_PROGRAM



PROGRAM _CYCLIC

	(* ============================================================= *)
	(* 0. LEITURA DA PLANTA: PRESSAO -> CM                          *)
	(* ============================================================= *)

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
	START: botao momentaneo NA, EDGEPOS(Start) arma LIGA.
	STOP:  botao NF (normal = TRUE), EDGENEG(Stop) detecta a parada.
	O teste NOT Stop impede religar com o circuito de STOP aberto.
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

		SomaY_Id := 0.0;
		SomaU_Id := 0.0;
		ContId := 0;
		ContSatId := 0;

		ContJanela := 0;
		ContEstavel := 0;

		ModeloEstavel := FALSE;
		ModeloValido := FALSE;
		ModeloAceito := FALSE;

		Degrau_Ativo := FALSE;

	END_IF;


	(* START somente com circuito de STOP fechado *)
	IF StartPulso AND Stop THEN

		LIGA := TRUE;

		(* [7] reinicia MQR e PI no modelo inicial (secao 2) *)
		ReiniciaModelo := TRUE;

		(* Comeca o setpoint interno no nivel atual *)
		SP_Rampa := y;
		y_f := y;

		(* [8] a partida tambem abre a identificacao *)
		TempoSemSP := 0.0;

		(* [9] integral comeca logo acima da zona morta da bomba *)
		Integral_PI := U_Partida;

		percentual := 0.0;
		u := 0.0;

		PrimeiraAmostra := TRUE;

		SomaY_Id := 0.0;
		SomaU_Id := 0.0;
		ContId := 0;
		ContSatId := 0;

		ContJanela := 0;
		ContEstavel := 0;

		ModeloEstavel := FALSE;
		ModeloValido := FALSE;
		ModeloAceito := FALSE;

		AtualizacoesPI := 0;

		(* Inicia a sequencia de degraus no SP, se habilitada *)
		IF Degrau_N > 10 THEN
			Degrau_N := 10;
		END_IF;

		Degrau_Ativo := EnsaioDegraus AND (Degrau_N > 0);
		Degrau_Concluido := FALSE;
		Degrau_Etapa := 0;
		Degrau_Cnt := 0;

	END_IF;



	(* ============================================================= *)
	(* 2. [7] MODELO INICIAL: NA PARTIDA DO CLP E A CADA START      *)
	(* ============================================================= *)

	IF ReiniciaModelo THEN

		(* modelo inicial dentro da faixa fisica do supervisor *)
		IF K_Ini < GanhoMinPl THEN
			K_Ini := GanhoMinPl;
		END_IF;

		IF K_Ini > GanhoMaxPl THEN
			K_Ini := GanhoMaxPl;
		END_IF;

		IF Tau_Ini < TauMinPl THEN
			Tau_Ini := TauMinPl;
		END_IF;

		IF Tau_Ini > TauMaxPl THEN
			Tau_Ini := TauMaxPl;
		END_IF;


		(* [1] amostras por periodo do MQR e limite do traco de P
		(recalculados a cada START: Ts_Id e P0 podem mudar no Watch) *)
		NAmostrasId := REAL_TO_INT(Ts_Id / Ts);

		IF NAmostrasId < 1 THEN
			NAmostrasId := 1;
		END_IF;

		TraceMax := 2.0 * (P0_Diag[0] + P0_Diag[1] + P0_Diag[2]);


		Theta0_Ini := EXP(-Ts_Id / Tau_Ini);
		Theta1_Ini := K_Ini * (1.0 - Theta0_Ini);

		Theta[0] := Theta0_Ini;
		Theta[1] := Theta1_Ini;
		Theta[2] := 0.0;

		OffsetIniciado := FALSE;

		FOR i := 0 TO 2 DO

			FOR j := 0 TO 2 DO
				P[i,j] := 0.0;
			END_FOR;

			P[i,i] := P0_Diag[i];

		END_FOR;


		GanhoPlanta := K_Ini;
		TauPlanta := Tau_Ini;


		(* PI base: mesma regra do adaptativo, sobre o modelo inicial *)
		Kp_Base :=
		(2.0 * ZetaDesejado * WnFactor - 1.0)
		/ K_Ini;

		Ti_Base :=
		(2.0 * ZetaDesejado * WnFactor - 1.0)
		* Tau_Ini
		/ (WnFactor * WnFactor);

		IF Kp_Base > KpMax THEN
			Kp_Base := KpMax;
		END_IF;

		IF Kp_Base < KpMin THEN
			Kp_Base := KpMin;
		END_IF;

		IF Ti_Base > TiMax THEN
			Ti_Base := TiMax;
		END_IF;

		IF Ti_Base < TiMin THEN
			Ti_Base := TiMin;
		END_IF;


		(* Toda partida comeca com PI base *)
		Kp_PI := Kp_Base;
		Ti_PI := Ti_Base;

		Kp_Alvo := Kp_Base;
		Ti_Alvo := Ti_Base;

		ReiniciaModelo := FALSE;

	END_IF;



	(* ============================================================= *)
	(* 3. SISTEMA LIGADO                                            *)
	(* ============================================================= *)

	IF LIGA THEN


		(* ========================================================= *)
		(* 4. [1] MEDIAS DE 1 s E MQR                               *)
		(* ========================================================= *)
		(*
		percentual, neste ponto, ainda e o comando calculado no ciclo
		anterior, ou seja, o que atuou sobre a planta ate a medida y
		atual. O MQR usa u em %.
		*)

		SomaY_Id := SomaY_Id + y;
		SomaU_Id := SomaU_Id + percentual;
		ContId := ContId + 1;

		(* [4] conta amostras fora da faixa util da bomba *)
		IF (percentual <= U_ZonaMorta) OR (percentual >= U_MaxId) THEN
			ContSatId := ContSatId + 1;
		END_IF;


		IF ContId >= NAmostrasId THEN

			y_med := SomaY_Id / INT_TO_REAL(NAmostrasId);
			u_med := SomaU_Id / INT_TO_REAL(NAmostrasId);

			(* [4] e [8]: atualiza somente com u efetivo e dentro do
			tempo de identificacao depois da ultima mudanca de SP *)
			IdLivre :=
			(ContSatId = 0)
			AND (TempoSemSP <= T_Excitacao);

			SomaY_Id := 0.0;
			SomaU_Id := 0.0;
			ContId := 0;
			ContSatId := 0;


			IF PrimeiraAmostra THEN

				y_prev := y_med;
				u_prev := u_med;

				PrimeiraAmostra := FALSE;

			ELSE


				(* ----------------------------------------------------- *)
				(* 4.1 Vetor de regressao (com termo constante [2])     *)
				(* ----------------------------------------------------- *)

				Phi[0] := y_prev;
				Phi[1] := u_prev;
				Phi[2] := 1.0;

				(* partida sem salto: ajusta Theta[2] na 1a amostra *)
				IF NOT OffsetIniciado THEN

					Theta[2] :=
					y_med
					- Theta[0] * Phi[0]
					- Theta[1] * Phi[1];

					OffsetIniciado := TRUE;

				END_IF;


				(* ----------------------------------------------------- *)
				(* 4.2 Predicao e erro de identificacao                 *)
				(* ----------------------------------------------------- *)

				Y_hat :=
				Theta[0] * Phi[0]
				+ Theta[1] * Phi[1]
				+ Theta[2] * Phi[2];

				Error := y_med - Y_hat;


				(* ----------------------------------------------------- *)
				(* 4.3 [4] Atualizacao somente com u efetivo            *)
				(* ----------------------------------------------------- *)

				IF IdLivre THEN

					(* PPhi = P*Phi *)
					FOR i := 0 TO 2 DO

						PPhi[i] :=
						P[i,0] * Phi[0]
						+ P[i,1] * Phi[1]
						+ P[i,2] * Phi[2];

					END_FOR;


					Den :=
					Lambda
					+ Phi[0] * PPhi[0]
					+ Phi[1] * PPhi[1]
					+ Phi[2] * PPhi[2];

					IF Den < 0.000000001 THEN
						Den := 0.000000001;
					END_IF;


					(* ganho do MQR e atualizacao de Theta *)
					FOR i := 0 TO 2 DO

						K[i] := PPhi[i] / Den;

						Theta[i] := Theta[i] + K[i] * Error;

					END_FOR;


					(* P = (P - K*(P*Phi)^T)/Lambda
					(P simetrica -> Phi^T*P = (P*Phi)^T) *)
					FOR i := 0 TO 2 DO

						FOR j := 0 TO 2 DO

							P[i,j] :=
							(P[i,j] - K[i] * PPhi[j])
							/ Lambda;

						END_FOR;

					END_FOR;


					(* [3] limita o traco de P *)
					TraceP := P[0,0] + P[1,1] + P[2,2];

					IF TraceP > TraceMax THEN

						FOR i := 0 TO 2 DO

							FOR j := 0 TO 2 DO
								P[i,j] := P[i,j] * TraceMax / TraceP;
							END_FOR;

						END_FOR;

					END_IF;

				END_IF;


				y_prev := y_med;
				u_prev := u_med;



				(* ===================================================== *)
				(* 5. [5] K E TAU INSTANTANEOS                         *)
				(* ===================================================== *)

				ModeloValido := FALSE;

				IF (Theta[0] > 0.0)
					AND (Theta[0] < 1.0)
					AND (Theta[1] > 0.0) THEN

					K_Inst :=
					Theta[1]
					/ (1.0 - Theta[0]);

					Tau_Inst :=
					-Ts_Id
					/ LN(Theta[0]);

					IF (K_Inst > GanhoMinPl)
						AND (K_Inst < GanhoMaxPl)
						AND (Tau_Inst > TauMinPl)
						AND (Tau_Inst < TauMaxPl) THEN

						ModeloValido := TRUE;

					END_IF;

				END_IF;



				(* ===================================================== *)
				(* 6. JANELA DAS ULTIMAS 10 ESTIMATIVAS (50 s)         *)
				(* ===================================================== *)
				(*
				So entram estimativas validas; uma invalida esvazia a
				janela.
				*)

				IF ModeloValido THEN

					IF ContJanela < 10 THEN

						KJanela[ContJanela] := K_Inst;
						TauJanela[ContJanela] := Tau_Inst;

						ContJanela := ContJanela + 1;

					ELSE

						FOR i := 0 TO 8 DO
							KJanela[i] := KJanela[i+1];
							TauJanela[i] := TauJanela[i+1];
						END_FOR;

						KJanela[9] := K_Inst;
						TauJanela[9] := Tau_Inst;

					END_IF;

				ELSE

					ContJanela := 0;

				END_IF;



				(* ===================================================== *)
				(* 7. [5] TESTE DE ESTABILIDADE                         *)
				(* ===================================================== *)

				ModeloEstavel := FALSE;

				IF ContJanela >= 10 THEN

					KMed := 0.0;
					TauMed := 0.0;

					KMinJ := KJanela[0];
					KMaxJ := KJanela[0];
					TauMinJ := TauJanela[0];
					TauMaxJ := TauJanela[0];

					FOR i := 0 TO 9 DO

						KMed := KMed + KJanela[i];
						TauMed := TauMed + TauJanela[i];

						IF KJanela[i] < KMinJ THEN
							KMinJ := KJanela[i];
						END_IF;

						IF KJanela[i] > KMaxJ THEN
							KMaxJ := KJanela[i];
						END_IF;

						IF TauJanela[i] < TauMinJ THEN
							TauMinJ := TauJanela[i];
						END_IF;

						IF TauJanela[i] > TauMaxJ THEN
							TauMaxJ := TauJanela[i];
						END_IF;

					END_FOR;

					KMed := KMed / 10.0;
					TauMed := TauMed / 10.0;

					ModeloEstavel :=
					((KMaxJ - KMinJ) < VarRelMaxK * KMed)
					AND
					((TauMaxJ - TauMinJ) < VarRelMaxTau * TauMed);

				END_IF;



				(* ===================================================== *)
				(* 8. CONFIRMACAO POR VARIAS JANELAS                    *)
				(* ===================================================== *)

				IF ModeloEstavel
					AND ModeloValido
					AND IdLivre THEN

					(* contador limitado: evita estouro do INT *)
					IF ContEstavel < EstavelNecessario THEN
						ContEstavel := ContEstavel + 1;
					END_IF;

				ELSE

					ContEstavel := 0;
					ModeloAceito := FALSE;

				END_IF;


				IF ContEstavel >= EstavelNecessario THEN

					ModeloAceito := TRUE;

					(* [5] filtro de 1a ordem dos parametros aceitos *)
					GanhoPlanta :=
					GanhoPlanta
					+ AlfaParam * (KMed - GanhoPlanta);

					TauPlanta :=
					TauPlanta
					+ AlfaParam * (TauMed - TauPlanta);



					(* ================================================= *)
					(* 9. RECALCULO DO PI SOMENTE NO MODO ADAPTATIVO    *)
					(* ================================================= *)

					IF PI_Adaptativo THEN

						Wn :=
						WnFactor
						/ TauPlanta;

						Kp_Alvo :=
						(2.0
						* ZetaDesejado
						* Wn
						* TauPlanta
						- 1.0)
						/ GanhoPlanta;

						Ti_Alvo :=
						(GanhoPlanta
						* Kp_Alvo)
						/ (TauPlanta
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


						AtualizacoesPI := AtualizacoesPI + 1;

					END_IF;

				END_IF;

			END_IF;

		END_IF;



		(* ========================================================= *)
		(* 10. ESCOLHA PI SIMPLES / PI ADAPTATIVO                   *)
		(* ========================================================= *)

		IF NOT PI_Adaptativo THEN

			(* PI simples sempre retorna aos ganhos base *)
			Kp_Alvo := Kp_Base;
			Ti_Alvo := Ti_Base;

		END_IF;



		(* ========================================================= *)
		(* 11. ALTERACAO SUAVE DOS GANHOS                           *)
		(* ========================================================= *)
		(*
		PI simples:    leva Kp/Ti suavemente de volta aos valores base.
		PI adaptativo: somente altera quando ModeloAceito = TRUE.
		*)

		IF (NOT PI_Adaptativo) OR ModeloAceito THEN


			(* ---------------- Kp ---------------- *)

			DeltaMax := KpRate * Ts;

			IF (Kp_Alvo - Kp_PI) > DeltaMax THEN

				Kp_PI := Kp_PI + DeltaMax;

			ELSIF (Kp_Alvo - Kp_PI) < -DeltaMax THEN

				Kp_PI := Kp_PI - DeltaMax;

			ELSE

				Kp_PI := Kp_Alvo;

			END_IF;


			(* ---------------- Ti ---------------- *)

			DeltaMax := TiRate * Ts;

			IF (Ti_Alvo - Ti_PI) > DeltaMax THEN

				Ti_PI := Ti_PI + DeltaMax;

			ELSIF (Ti_Alvo - Ti_PI) < -DeltaMax THEN

				Ti_PI := Ti_PI - DeltaMax;

			ELSE

				Ti_PI := Ti_Alvo;

			END_IF;

		END_IF;



		(* ========================================================= *)
		(* 12. SEQUENCIA DE DEGRAUS NO SETPOINT                     *)
		(* ========================================================= *)
		(*
		Cada degrau dura Degrau_Tempo segundos.
		O SP passa pela rampa (secao 13) normalmente.
		*)

		IF Degrau_Ativo THEN

			(* fim do degrau atual: avanca para o proximo *)
			IF DINT_TO_REAL(Degrau_Cnt) * Ts
				>= Degrau_Tempo - 0.5 * Ts THEN

				Degrau_Etapa := Degrau_Etapa + 1;
				Degrau_Cnt := 0;

			END_IF;


			IF Degrau_Etapa >= Degrau_N THEN

				(* fim da sequencia: SP fica no ultimo degrau *)
				Degrau_Ativo := FALSE;
				Degrau_Concluido := TRUE;

			ELSE

				SP := Degrau_Valor[Degrau_Etapa];

				Degrau_Cnt := Degrau_Cnt + 1;

			END_IF;

		END_IF;



		(* ========================================================= *)
		(* 13. RAMPA DO SETPOINT                                    *)
		(* ========================================================= *)

		(* [8] tempo desde a ultima mudanca de SP (limitado para nao
		perder resolucao no REAL) *)
		IF ABS(SP - SP_Anterior) > 0.1 THEN
			TempoSemSP := 0.0;
		ELSIF TempoSemSP < 10000.0 THEN
			TempoSemSP := TempoSemSP + Ts;
		END_IF;

		SP_Anterior := SP;


		DeltaMax := TaxaSP * Ts;

		IF (SP - SP_Rampa) > DeltaMax THEN

			SP_Rampa := SP_Rampa + DeltaMax;

		ELSIF (SP - SP_Rampa) < -DeltaMax THEN

			SP_Rampa := SP_Rampa - DeltaMax;

		ELSE

			SP_Rampa := SP;

		END_IF;



		(* ========================================================= *)
		(* 14. CONTROLADOR PI                                       *)
		(* ========================================================= *)

		(* [6] medicao filtrada: reduz o ruido amplificado por Kp *)
		IF TfMedicao > Ts THEN
			y_f := y_f + (Ts / TfMedicao) * (y - y_f);
		ELSE
			y_f := y;
		END_IF;

		Erro_PI := SP_Rampa - y_f;


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
		(* 16. % -> COMANDO BRUTO DO INVERSOR (igual ao anterior)   *)
		(* ========================================================= *)
		(*
		percentual = 0   -> potencia = 1000 (minimo)
		percentual = 50  -> potencia = 16000
		percentual = 100 -> potencia = 32000
		*)

		potencia := REAL_TO_INT(percentual * 320.0);

		IF potencia > 32000 THEN
			potencia := 32000;
		END_IF;

		IF potencia < 1000 THEN
			potencia := 1000;
		END_IF;


		(* comando aplicado neste ciclo, em % *)
		u := percentual;


	ELSE


		(* ========================================================= *)
		(* 17. SISTEMA PARADO                                       *)
		(* ========================================================= *)

		potencia := 0;

		percentual := 0.0;
		u := 0.0;

		SaidaPI := 0.0;

		Integral_PI := 0.0;
		Integral_Candidato := 0.0;

		SP_Rampa := y;
		y_f := y;

		PrimeiraAmostra := TRUE;

		SomaY_Id := 0.0;
		SomaU_Id := 0.0;
		ContId := 0;
		ContSatId := 0;

		ContEstavel := 0;

		ModeloAceito := FALSE;

	END_IF;

END_PROGRAM
