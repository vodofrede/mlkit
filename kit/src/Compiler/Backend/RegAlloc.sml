functor RegAlloc(structure PhysSizeInf : PHYS_SIZE_INF
                 structure Con : CON
		 structure Excon : EXCON
		 structure Lvars : LVARS
		 structure Effect : EFFECT
		 structure Labels : ADDRESS_LABELS
		 structure CallConv: CALL_CONV
		 structure LineStmt: LINE_STMT
	           sharing type Con.con = LineStmt.con
                   sharing type Excon.excon = LineStmt.excon
                   sharing type Lvars.lvar = LineStmt.lvar = CallConv.lvar
                   sharing type Effect.effect = Effect.place = LineStmt.place
                   sharing type Labels.label = LineStmt.label
                   sharing type CallConv.cc = LineStmt.cc
		   sharing type LineStmt.phsize = PhysSizeInf.phsize
		 structure BI : BACKEND_INFO
		 structure PP : PRETTYPRINT
		   sharing type PP.StringTree = 
                                Effect.StringTree = 
				LineStmt.StringTree
                 structure Flags : FLAGS
		 structure Report : REPORT
		   sharing type Report.Report = Flags.Report
		 structure Crash : CRASH) : REG_ALLOC =
struct

  type place = Effect.place
  type excon = Excon.excon
  type con = Con.con
  type lvar = Lvars.lvar
  type phsize = PhysSizeInf.phsize
  type pp = PhysSizeInf.pp
  type cc = CallConv.cc
  type label = Labels.label
  type ('sty,'offset) LinePrg = ('sty,'offset) LineStmt.LinePrg
  type phreg = LineStmt.phreg

  datatype StoreType =
    STACK_STY of lvar
  | PHREG_STY of lvar * phreg
    
  fun pr_sty(STACK_STY lv) = Lvars.pr_lvar lv ^ ":stack"
    | pr_sty(PHREG_STY(lv,i)) = Lvars.pr_lvar lv ^ ":phreg" ^ Word.toString i

  (***********)
  (* Logging *)
  (***********)
  fun log s = TextIO.output(!Flags.log,s ^ "\n")
  fun msg s = TextIO.output(TextIO.stdOut, s)
  fun chat(s: string) = if !Flags.chat then msg (s) else ()
  fun die s  = Crash.impossible ("RegAlloc." ^ s)
  fun fast_pr stringtree = 
    (PP.outputTree ((fn s => TextIO.output(!Flags.log, s)) , stringtree, !Flags.colwidth);
     TextIO.output(!Flags.log, "\n"))

  fun display(title, tree) =
    fast_pr(PP.NODE{start=title ^ ": ",
		    finish="",
		    indent=3,
		    children=[tree],
		    childsep=PP.NOSEP
		    })

  (****************************************************************)
  (* Add Dynamic Flags                                            *)
  (****************************************************************)

  val _ = List.app (fn (x,y,r) => Flags.add_flag_to_menu (["Printing of intermediate forms"],x,y,r))
    [("print_register_allocated_program", "print register allocated program (LineStmt)", ref false)]

  (***********************)
  (* Register Allocation *)
  (***********************)
  local
    (*************************************************)
    (* Make Call Conventions Explicit at Call Points *)
    (*************************************************)
    local
      fun resolve_args([],lss) = lss
	| resolve_args((atom,i)::args,lss) = 
	resolve_args(args,LineStmt.ASSIGN{pat=atom,bind=LineStmt.ATOM(LineStmt.PHREG i)}::lss)

      fun resolve_res([],lss) = lss
	| resolve_res((atom,i)::res,lss) = 
	resolve_res(res,LineStmt.ASSIGN{pat=LineStmt.PHREG i,bind=LineStmt.ATOM atom}::lss)

      fun CC_sw CC_lss (LineStmt.SWITCH(atom_arg,sels,default)) =
	LineStmt.SWITCH(atom_arg,map (fn (s,lss) => (s,CC_lss lss)) sels, CC_lss default)

      fun CC_ls(LineStmt.FNJMP{opr,args,clos,free,res},rest) =
	let
	  val ({clos,args,free,res,...},assign_list_args,assign_list_res) = 
	    CallConv.resolve_app LineStmt.PHREG {clos=clos,free=free,args=args,reg_vec=NONE,reg_args=[],res=res}
	in
	  resolve_res(assign_list_args,
		      LineStmt.FNJMP{opr=opr,args=args,clos=clos,free=free,res=res}::
		      resolve_args(assign_list_res,rest))
	end
	| CC_ls(LineStmt.FNCALL{opr,args,clos,free,res},rest) =
	let
	  val ({clos,args,free,res,...},assign_list_args,assign_list_res) = 
	    CallConv.resolve_app LineStmt.PHREG {clos=clos,free=free,args=args,reg_vec=NONE,reg_args=[],res=res}
	in
	  resolve_res(assign_list_args,
		      LineStmt.FNCALL{opr=opr,args=args,clos=clos,free=free,res=res}::
		      resolve_args(assign_list_res,rest))
	end
	| CC_ls(LineStmt.JMP{opr,args,reg_vec,reg_args,clos,free,res},rest) =
	let
	  val ({clos,args,free,res,reg_vec,reg_args},assign_list_args,assign_list_res) = 
	    CallConv.resolve_app LineStmt.PHREG {clos=clos,free=free,args=args,reg_vec=reg_vec,reg_args=reg_args,res=res}
	in
	  resolve_res(assign_list_args,
		      LineStmt.JMP{opr=opr,args=args,reg_vec=reg_vec,reg_args=reg_args,clos=clos,free=free,res=res}::
		      resolve_args(assign_list_res,rest))
	end
	| CC_ls(LineStmt.FUNCALL{opr,args,reg_vec,reg_args,clos,free,res},rest) =
	let
	  val ({clos,args,free,res,reg_vec,reg_args},assign_list_args,assign_list_res) = 
	    CallConv.resolve_app LineStmt.PHREG {clos=clos,free=free,args=args,reg_vec=reg_vec,reg_args=reg_args,res=res}
	in
	  resolve_res(assign_list_args,
		      LineStmt.FUNCALL{opr=opr,args=args,reg_vec=reg_vec,reg_args=reg_args,clos=clos,free=free,res=res}::
		      resolve_args(assign_list_res,rest))
	end
	| CC_ls(LineStmt.LETREGION{rhos,body},rest) = LineStmt.LETREGION{rhos=rhos,body=CC_lss body}::rest
	| CC_ls(LineStmt.SCOPE{pat,scope},rest) = LineStmt.SCOPE{pat=pat,scope=CC_lss scope}::rest
	| CC_ls(LineStmt.HANDLE(lss1,lss2,offset),rest) = LineStmt.HANDLE(CC_lss lss1,CC_lss lss2,offset)::rest
	| CC_ls(LineStmt.SWITCH_I sw,rest) = LineStmt.SWITCH_I(CC_sw CC_lss sw)::rest
	| CC_ls(LineStmt.SWITCH_S sw,rest) = LineStmt.SWITCH_S(CC_sw CC_lss sw)::rest
	| CC_ls(LineStmt.SWITCH_C sw,rest) = LineStmt.SWITCH_C(CC_sw CC_lss sw)::rest
	| CC_ls(LineStmt.SWITCH_E sw,rest) = LineStmt.SWITCH_E(CC_sw CC_lss sw)::rest
	| CC_ls(LineStmt.CCALL{name,args,rhos_for_result,res},rest) = 
	let
	  val ({args,rhos_for_result,res},assign_list_args,assign_list_res) = 
	    CallConv.resolve_ccall LineStmt.PHREG {args=args,rhos_for_result=rhos_for_result,res=res}
	in
	  resolve_res(assign_list_args,
		      LineStmt.CCALL{name=name,args=args,rhos_for_result=rhos_for_result,res=res}::
		      resolve_args(assign_list_res,rest))
	end
	| CC_ls (ls,rest) = ls::rest
	
      and CC_lss(lss) = List.foldr (fn (ls,acc) => CC_ls(ls,acc)) [] lss
    in
      fun CC_top_decl(LineStmt.FUN(lab,cc,lss)) = 
	let
	  val (cc',args,res) = CallConv.resolve_cc(cc)
	  val args' = map (fn (lv,i) => (LineStmt.VAR lv,i)) args
	  val res' = map (fn (lv,i) => (LineStmt.VAR lv,i)) res
	  val body_lss = CC_lss(lss)
	  val body_args = 
	     LineStmt.SCOPE{pat=map #1 args,scope=resolve_args(args',body_lss)}
	  val body_res =
	    LineStmt.SCOPE{pat=map #1 res,scope=body_args::resolve_res(res',[])}
	in
	  LineStmt.FUN(lab,cc',[body_res])
	end
	| CC_top_decl(LineStmt.FN(lab,cc,lss)) = 
	let
	  val (cc',args,res) = CallConv.resolve_cc(cc)
	  val args' = map (fn (lv,i) => (LineStmt.VAR lv,i)) args
	  val res' = map (fn (lv,i) => (LineStmt.VAR lv,i)) res
	  val body_lss = CC_lss(lss)
	  val body_args = 
	    LineStmt.SCOPE{pat=map #1 args,scope=resolve_args(args',body_lss)}
	  val body_res =
	     LineStmt.SCOPE{pat=map #1 res,scope=body_args::resolve_res(res',[])}
	in
	  LineStmt.FN(lab,cc',[body_res])
	end
    end

    (*****************************)
    (* DUMMY REGISTER ALLOCATION *)
    (*****************************)
    local
      fun assign_stack(lv) = STACK_STY lv

      fun ra_dummy_sw ra_dummy_lss (LineStmt.SWITCH(atom_arg,sels,default)) =
	LineStmt.SWITCH(atom_arg,map (fn (s,lss) => (s,ra_dummy_lss lss)) sels, ra_dummy_lss default)

      fun ra_dummy_ls(LineStmt.ASSIGN a,rest) = LineStmt.ASSIGN a::rest
	| ra_dummy_ls(LineStmt.FLUSH a,rest) = die "ra_dummy_ls: FLUSH not inserted yet."
	| ra_dummy_ls(LineStmt.FETCH a,rest) = die "ra_dummy_ls: FETCH not inserted yet."
	| ra_dummy_ls(LineStmt.FNJMP a,rest) = LineStmt.FNJMP a::rest
	| ra_dummy_ls(LineStmt.FNCALL a,rest) = LineStmt.FNCALL a::rest
	| ra_dummy_ls(LineStmt.JMP a,rest) = LineStmt.JMP a::rest
	| ra_dummy_ls(LineStmt.FUNCALL a,rest) = LineStmt.FUNCALL a::rest
	| ra_dummy_ls(LineStmt.LETREGION{rhos,body},rest) = LineStmt.LETREGION{rhos=rhos,body=ra_dummy_lss body}::rest
	| ra_dummy_ls(LineStmt.SCOPE{pat,scope},rest) = 
	LineStmt.SCOPE{pat=map assign_stack pat,scope=ra_dummy_lss scope}::rest
	| ra_dummy_ls(LineStmt.HANDLE(lss1,lss2,offset),rest) = LineStmt.HANDLE(ra_dummy_lss lss1,ra_dummy_lss lss2,offset)::rest
	| ra_dummy_ls(LineStmt.RAISE{arg,defined_atoms},rest) = LineStmt.RAISE{arg=arg,defined_atoms=defined_atoms}::rest
	| ra_dummy_ls(LineStmt.SWITCH_I sw,rest) = LineStmt.SWITCH_I(ra_dummy_sw ra_dummy_lss sw)::rest
	| ra_dummy_ls(LineStmt.SWITCH_S sw,rest) = LineStmt.SWITCH_S(ra_dummy_sw ra_dummy_lss sw)::rest
	| ra_dummy_ls(LineStmt.SWITCH_C sw,rest) = LineStmt.SWITCH_C(ra_dummy_sw ra_dummy_lss sw)::rest
	| ra_dummy_ls(LineStmt.SWITCH_E sw,rest) = LineStmt.SWITCH_E(ra_dummy_sw ra_dummy_lss sw)::rest
	| ra_dummy_ls(LineStmt.RESET_REGIONS a,rest) = LineStmt.RESET_REGIONS a::rest
	| ra_dummy_ls(LineStmt.CCALL a,rest) = LineStmt.CCALL a::rest

      and ra_dummy_lss(lss) = List.foldr (fn (ls,acc) => ra_dummy_ls(ls,acc)) [] lss

      fun ra_dummy_top_decl(f) =
	(case CC_top_decl f of
	   LineStmt.FUN(lab,cc,lss) => LineStmt.FUN(lab,cc,ra_dummy_lss lss)
	 | LineStmt.FN(lab,cc,lss) => LineStmt.FN(lab,cc,ra_dummy_lss lss))
    in
      fun ra_dummy_prg funcs =
	List.foldr (fn (func,acc) => ra_dummy_top_decl func :: acc) [] funcs
    end

    (***************************************)
    (* REGISTER ALLOCATION WITH COALESCING *)
    (***************************************)
    local
    in
      fun ra_prg(f) = die "ra: REGISTER ALLOCATION WITH COALESCING not implemented"
    end

    (******************************************************)
    (* Funtion to invoke the register allocator of choice *)
    (******************************************************)
    fun ra_main {main_lab:label,
		 code=line_prg: (lvar,unit) LinePrg,
		 imports:label list,
		 exports:label list} ra_prg =
      let
	val _ = chat "[Register allocation..."
	val line_prg_ra = ra_prg line_prg
	val _ = 
	  if Flags.is_on "print_register_allocated_program" then
	    display("\nReport: AFTER REGISTER ALLOCATION (dummy):", LineStmt.layout_line_prg pr_sty (fn _ => "()") line_prg_ra)
	  else
	    ()
	val _ = chat "]\n"
      in
	{main_lab=main_lab,code=line_prg_ra: (StoreType,unit) LinePrg,imports=imports,exports=exports}
      end
  in
    fun ra_dummy code = ra_main code ra_dummy_prg
    fun ra code = ra_main code ra_prg
  end

end;
