(********************************************************************
 * COPYRIGHT --  
 ********************************************************************
 * Program: NewProgram
 * File: NewProgram.typ
 * Author: joao.paulo
 * Created: August 13, 2026
 ********************************************************************
 * Local data types of program NewProgram
 ********************************************************************)

TYPE
	EtapaColeta_enum :
		(
		COLETA_PARADO := 0, (* sequencia parada *)
		COLETA_SUBIDA := 1, (* patamar aplicado, aguarda pressao alta *)
		COLETA_DESCIDA := 2, (* potencia zerada, aguarda pressao baixa *)
		COLETA_FIM := 3 (* os N_CICLOS ciclos foram concluidos *)
		);
END_TYPE
