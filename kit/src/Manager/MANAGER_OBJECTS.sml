(*$MANAGER_OBJECTS *)

signature MANAGER_OBJECTS =
  sig
    type modcode and target and linkinfo and StringTree

    structure ModCode :
      sig
	val empty : modcode
	val seq : modcode * modcode -> modcode
	val mk_modcode : target * linkinfo * string -> modcode   (* Use emit or mk_exe to actually emit code.
								  * The string is a unit name. *)
	val emit : modcode -> modcode       
	val mk_exe : modcode * string -> unit   (* produces executable `string' in target directory *)
      end
    
    type filepath sharing type filepath = string    (* absolute path *)
    type filename sharing type filename = string    (* just filename *)
    type funstamp and funid
    structure FunStamp :
      sig
	val new : funid -> funstamp
	val from_filemodtime : filepath -> funstamp
	val eq : funstamp * funstamp -> bool
      end

    val funid_from_filename : filename -> funid
    val funid_to_filename : funid -> filename

    type IntFunEnv and IntBasis and ElabEnv and strexp and strid
    structure IntFunEnv :
      sig
	val empty : IntFunEnv
	val initial : IntFunEnv
	val plus : IntFunEnv * IntFunEnv -> IntFunEnv
	val add : funid * (funstamp * strid * ElabEnv * strexp * IntBasis) * IntFunEnv -> IntFunEnv
	val lookup : IntFunEnv -> funid -> funstamp * strid * ElabEnv * strexp * IntBasis  
	val restrict : IntFunEnv * funid list -> IntFunEnv
	val enrich : IntFunEnv * IntFunEnv -> bool  (* using funstamps *)
	val layout : IntFunEnv -> StringTree
      end

    type CEnv and CompileBasis and id
    structure IntBasis :
      sig
	val mk : IntFunEnv * CEnv * CompileBasis -> IntBasis
	val un : IntBasis -> IntFunEnv * CEnv * CompileBasis
	val empty : IntBasis
	val initial : IntBasis
	val plus : IntBasis * IntBasis -> IntBasis
	val restrict : IntBasis * (funid list * strid list * id list) -> IntBasis
	val match : IntBasis * IntBasis -> IntBasis
	val enrich : IntBasis * IntBasis -> bool
	val layout : IntBasis -> StringTree
      end

    type Basis and InfixBasis and ElabBasis and sigid and tycon
    structure Basis :
      sig
	val initial : Basis
	val empty : Basis
	val mk : InfixBasis * ElabBasis * IntBasis -> Basis
	val un : Basis -> InfixBasis * ElabBasis * IntBasis
	val plus : Basis * Basis -> Basis
	val eq : Basis * Basis -> bool
	val restrict : Basis * {ids : id list, tycons : tycon list,
				strids : strid list, funids : funid list,
				sigids : sigid list} -> Basis
	val enrich : Basis * Basis -> bool
	val match : Basis * Basis -> Basis
	val layout : Basis -> StringTree
      end

    type name
    structure Repository :
      sig
	val clear : unit -> unit
	val delete_entry : funid -> unit
	val lookup_elabRep : funid -> 
	  (InfixBasis * ElabBasis * (name list * InfixBasis * ElabBasis)) list

	  (* Repository lookup's only return entries which are
	   * reusable (i.e. where all export (ty-)names are marked
	   * generative.) In particular, this means that entries which
	   * have just been added, are not returned by a lookup, prior
	   * to ``recovering.'' *)

	val add_elabRep : funid * (InfixBasis * ElabBasis * (name list * InfixBasis * ElabBasis)) -> unit
	val add_intRep : funid * (funstamp * IntBasis * name list * modcode * IntBasis) -> unit
	val lookup_intRep : funid -> (funstamp * IntBasis * name list * modcode * IntBasis) list
	val recover : unit -> unit

          (* Before building a project the repository should be
	   * ``recovered'' meaning that all export names are marked
	   * generative (see NAME). Then when an entry is reused,
	   * export names are marked non-generative (for an entry to
	   * be reused all export names must be marked generative.) *)

      end
    
  end