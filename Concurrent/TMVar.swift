//
//  TMVar.swift
//  Parallel-iOS
//
//  Created by Robert Widmann on 9/28/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Swiftz

public struct TMVar<A> {
	let tvar : TVar<Optional<A>>

	init(_ tvar : TVar<Optional<A>>) {
		self.tvar = tvar
	}
	
	public init() {
		self.init(TVar(.None))
	}

	public init(initial : A) {
		let t : TVar<Optional<A>> = TVar(.Some(initial))
		self.init(t)
	}
}

public func newTMVar<A>(x : A) -> STM<TMVar<A>> {
	return do_ { () -> TMVar<A> in
		let t : TVar<Optional<A>> = !newTVar(Optional.Some(x))
		return TMVar(t)
	}
}

public func newEmptyTMVar<A>() -> STM<TMVar<A>> {
	return do_ { () -> TMVar<A> in
		let t : TVar<Optional<A>>! = !newTVar(.None)
		return TMVar(t)
	}
}

public func takeTMVar<A>(t : TMVar<A>) -> STM<A> {
	return do_ {
		let m : Optional<A> = !t.tvar.read()
		switch m {
			case .None:
				return retry()
			case .Some(let a):
				return do_ { () -> A in
					t.tvar.write(.None)
					return a
				}
		}
	}
}

public func tryTakeTMVar<A>(t : TMVar<A>) -> STM<Optional<A>> {
	return do_ {
		let m : Optional<A> = !t.tvar.read()
		switch m {
			case .None:
				return do_ { () in .None }
			case .Some(let a):
				return do_ { () -> Optional<A> in
					t.tvar.write(.None)
					return .Some(a)
				}
		}
	}
}

public func putTMVar<A>(t : TMVar<A>) -> A -> STM<()> {
	return { x in
		do_ {
			let m : Optional<A> = !t.tvar.read()
			switch m {
				case .Some(_):
					return retry()
				case .None:
					return t.tvar.write(.Some(x))
			}
		}
	}
}

public func tryPutTMVar<A>(t : TMVar<A>) -> A -> STM<Bool> {
	return { x in
		do_ {
			let m : Optional<A> = !t.tvar.read()
			switch m {
				case .Some(_):
					return do_ { () in false }
				case .None:
					return do_ { () -> Bool in
						!t.tvar.write(.Some(x))
						return true
					}
			}
		}
	}
}

public func readTMVar<A>(t : TMVar<A>) -> STM<A> {
	return do_ {
		let m : Optional<A> = !t.tvar.read()
		switch m {
			case .None:
				return retry()
			case .Some(let a):
				return do_ { () in a }
		}
	}
}

public func tryReadTMVar<A>(t : TMVar<A>) -> STM<Optional<A>> {
	return t.tvar.read()
}

public func swapTMVar<A>(t : TMVar<A>) -> A -> STM<A> {
	return { x in
		do_ {
			let m : Optional<A> = !t.tvar.read()
			switch m {
				case .None:
					return retry()
				case .Some(let a):
					return do_ { () -> A in
						!t.tvar.write(.Some(x))
						return a
					}
			}
		}
	}
}

public func isEmptyTMVar<A>(t : TMVar<A>) -> STM<Bool> {
	return do_ { () -> Bool in
		let m : Optional<A> = !t.tvar.read()
		switch m {
			case .None:
				return true
			case .Some(_):
				return false
		}
	}
}


