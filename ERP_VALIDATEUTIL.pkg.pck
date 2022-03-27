CREATE OR REPLACE PACKAGE ERP_VALIDATEUTIL
AS
  -- Created on 28/03/2022 by Kpriyadarshan
  FUNCTION getElection(inElctId  IN  Election.Id%TYPE) RETURN common_type.t_electCoverage;
                       
  FUNCTION getElectionAmt(inElectId IN Election.Id%TYPE) RETURN NUMBER;
  
  PROCEDURE balanceValidate(inClmAmt      IN  NUMBER,
                            ot_TabClmInfo OUT NOCOPY common_type.t_claimInfo
                           );
                           
END ERP_VALIDATEUTIL;
/
CREATE OR REPLACE PACKAGE BODY ERP_VALIDATEUTIL
AS
  
  FUNCTION getElection(inElctId  IN  Election.Id%TYPE) RETURN common_type.t_electCoverage IS
    v_stkCnt           NUMBER := 0;
    v_colCnt           NUMBER := 0;
    
    t_TabelectCoverage common_type.t_electCoverage;
    t_RecElectCoverage common_type.electCoverage;
    t_TabstkCovrage    common_type.t_stkCovrage;
    rElect             common_type.electCoverage;
    rStkElect          common_type.stkCovrage;
  BEGIN
    
    FOR curElect IN (SELECT *
                     FROM Election e
                     WHERE e.id = inElctId
                    ) LOOP
      
      rElect.Id                 := curElect.id;
      rElect.Begins             := curElect.begins;
      rElect.Ends               := curElect.ends;
      rElect.Elect_Amt          := curElect.elect_amt;
      rElect.Elect_Ava_Bal      := curElect.elect_ava_bal;
      rElect.Elect_Deposit_Bal  := curElect.elect_deposit_bal;
      rElect.Can_Pay_Upto_Elect := curElect.can_pay_upto_elect;
      
      t_TabelectCoverage.Delete;
      v_colCnt := 1;
      t_TabelectCoverage(v_colCnt) := rElect;
      t_RecElectCoverage := t_TabelectCoverage(v_colCnt);
      
      SELECT count(st.elct_id)
        INTO v_stkCnt
      FROM Stack_Election st
      WHERE st.elct_id = inElctId;
      
      IF v_stkCnt > 0 THEN
        
        FOR curStk IN (SELECT *
                       FROM Stack_Election e
                       WHERE e.id = curElect.Id
                      ) LOOP
         
          rStkElect.id := curStk.id;
          rStkElect.elct_id := curStk.elct_id;
          rStkElect.begins := curStk.begins;
          rStkElect.ends := curStk.ends;
          rStkElect.stk_elect_amt := curStk.stk_elect_amt;
          rStkElect.stk_elect_ava_bal := curStk.stk_elect_ava_bal;
          
          v_colCnt := t_TabelectCoverage.Count + 1;
          t_TabstkCovrage(v_colCnt) := rStkElect;
          t_RecElectCoverage.STKINFOREC := t_TabstkCovrage(v_colCnt);
        END LOOP;
      END IF;
    END LOOP;
    
    t_TabelectCoverage(1) := t_RecElectCoverage;
    
    return t_TabelectCoverage;
  
  END getElection;
                       
  FUNCTION getElectionAmt(inElectId IN Election.Id%TYPE) RETURN NUMBER IS
    cnAmount        Election.Elect_Amt%TYPE;
    t_Tabelect      common_type.t_electCoverage;
    t_RecElect      common_type.electCoverage;
    t_TabClmInfo    common_type.t_claimInfo;
    t_RecClmInfo    common_type.claimInfo;
    t_RecClmInfo_SP common_type.claimInfo;
  BEGIN
    
    t_Tabelect := getElection(inElctId => inElectId);
    
    FOR i IN t_Tabelect.FIRST.. t_Tabelect.LAST LOOP
      t_RecElect := t_Tabelect(i);
      IF t_RecElect.can_pay_upto_elect = 'Y' THEN
        IF t_RecElect.elect_amt > 0 THEN
          cnAmount := t_RecElect.elect_amt;
        END IF;
      ELSE
        IF t_RecElect.elect_amt > 0 AND 
          t_RecElect.elect_amt <= t_RecElect.stkinforec.stk_elect_amt THEN
          cnAmount := t_RecElect.elect_amt;
        ELSE
          cnAmount := t_RecElect.stkinforec.stk_elect_amt;
        END IF;
      END IF;
    END LOOP;
    -- Check Rule Level Amount
    balanceValidate(inClmAmt => cnAmount, ot_TabClmInfo => t_TabClmInfo);
    
    FOR clm IN t_TabClmInfo.FIRST.. t_TabClmInfo.LAST LOOP
      IF clm = 1 THEN
        t_RecClmInfo := t_TabClmInfo(clm);
        dbms_output.put_line('Claim Amount: '||t_RecClmInfo.clm_amt);
                             
      ELSIF clm = 2 THEN
        t_RecClmInfo_SP := t_TabClmInfo(clm);
        dbms_output.put_line('Denied Amount: '||t_RecClmInfo_SP.clm_amt||chr(10)||
                             'Remain Amt: '||t_RecClmInfo_SP.rem_amt||chr(10)||
                             'Denial Reason: '||t_RecClmInfo_SP.denial_reason
                            );
      END IF;
    END LOOP;
    
    
    RETURN cnAmount;
    
  END getElectionAmt;
  
  PROCEDURE balanceValidate(inClmAmt      IN  NUMBER,
                            ot_TabClmInfo OUT NOCOPY common_type.t_claimInfo
                           ) IS
  
    t_RecClmInfo    common_type.claimInfo;
    t_RecClmInfo_SP common_type.claimInfo;
  
    cnRuleAmt       NUMBER := 100;
    cnApprvAmt      NUMBER;
    cnDeniedAmt     NUMBER;
    cnRemainAmt     NUMBER;
  BEGIN
    IF inClmAmt > 0 THEN
      IF cnRuleAmt > inClmAmt THEN
        t_RecClmInfo.clm_amt := inClmAmt;
      ELSE
        t_RecClmInfo.clm_amt           := cnRuleAmt;
        cnDeniedAmt                    := inClmAmt - cnRuleAmt;
        cnRemainAmt                    := t_RecClmInfo.clm_amt - cnRuleAmt;
        t_RecClmInfo.rem_amt           := cnRemainAmt;
        t_RecClmInfo_SP.clm_amt        := cnDeniedAmt;
        t_RecClmInfo_SP.denial_reason  := 'Claim Denied with '||t_RecClmInfo_SP.clm_amt||' Amount';
      END IF;
    ELSE
      t_RecClmInfo.clm_amt := 0;
    END IF;
    
    ot_TabClmInfo(1) := t_RecClmInfo;
    ot_TabClmInfo(2) := t_RecClmInfo_SP;
    
  END balanceValidate;
  
END ERP_VALIDATEUTIL;
/
