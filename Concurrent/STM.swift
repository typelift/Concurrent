//
//  STM.swift
//  Basis
//
//  Created by Robert Widmann on 9/15/14.
//  Copyright (c) 2014 Robert Widmann. All rights reserved.
//

import Swiftx

public class STM<A> : K1<A> {
	typealias B = Any

	let act : STMD<A>


	init(_ act : STMD<A>) {
		self.act = act
	}

	public func destruct() -> STMD<A> {
		return self.act
	}
}

extension STM : Functor {
	typealias FA = STM<A>

	public class func fmap<B>(f: A -> B) -> STM<A> -> STM<B> {
		return { x in x >>- { y in STM<B>.pure(f(y)) } }
	}
}

public func <%><A, B>(f: A -> B, io : STM<A>) -> STM<B> {
	return STM.fmap(f)(io)
}

public func <% <A, B>(x : A, io : STM<B>) -> STM<A> {
	return STM.fmap(const(x))(io)
}

extension STM : Applicative {
	public class func pure(a: A) -> STM<A> {
		return STM<A>(STMD<A>.Return(a))
	}

}

public func <*><A, B>(fn: STM<A -> B>, m: STM<A>) -> STM<B> {
	return !fn <%> m
}

public func *> <A, B>(a : STM<A>, b : STM<B>) -> STM<B> {
	return const(id) <%> a <*> b
}

public func <* <A, B>(a : STM<A>, b : STM<B>) -> STM<A> {
	return const <%> a <*> b
}

extension STM : Monad {
	public func bind<B>(f: A -> STM<B>) -> STM<B> {
		return STM<B>(self.destruct().bind({ a in f(a).destruct() }))
	}
}


public func >>-<A, B>(x: STM<A>, f: A -> STM<B>) -> STM<B> {
	return x.bind(f)
}

public func >><A, B>(x: STM<A>, y: STM<B>) -> STM<B> {
	return x.bind({ (_) in
		return y
	})
}

public prefix func !<A>(stm: STM<A>) -> A {
	return !atomically(stm)
}

public func do_<A>(fn: () -> A) -> STM<A> {
	return STM<A>(STMD<A>.Return(fn()))
}

public func do_<A>(fn: () -> STM<A>) -> STM<A> {
	return fn()
}

public enum STMD<A> {
	case Return(@autoclosure() -> A)
	case NewTVar(@autoclosure() -> A, TVar<A>, A -> STM<A>)
	case ReadTVar(TVar<A>, A -> STM<A>)
	case WriteTVar(TVar<A>, @autoclosure() -> A, STM<A>)
	case Retry
	case OrElse(STM<A>, STM<A>, (A -> STM<A>))

	public func bind<B>(f: A -> STMD<B>) -> STMD<B> {
		switch self {
			case .Return(let x):
				return f(x())
			case .Retry:
				return STMD<B>.Retry
			case .NewTVar(let x, _, let cont):
				return cont(x()).destruct().bind(f)
			case .ReadTVar(let x, let cont):
				return STM<B>(cont(!readMVar((!readMVar(x.tvar)).globalContent)).destruct().bind(f)).destruct()
			case .WriteTVar(let v, let x, let cont):
				return cont.destruct().bind({ _ in f(!readMVar((!readMVar(v.tvar)).globalContent)) })
			case .OrElse(let a1, let a2, let cont):
				return a1.destruct().bind({ i in cont(i).destruct().bind(f) })
		}
	}
}

public func orElse<A>(a1 : STM<A>)(a2 : STM<A>) -> STM<A> {
	return STM(STMD<A>.OrElse(a1, a2, { x in STM(STMD.Return(x)) }))
}

public func retry<A>() -> STM<A> {
	return STM(STMD<A>.Retry)
}

public func newTVarIO<A>(x : A) -> IO<TVar<A>> {
	return atomically(newTVar(x))
}

public func atomically<A>(act : STM<A>) -> IO<A> {
	return do_ {
		let tlog : IORef<TransactionLog<A>> = !emptyTLOG()
		return performSTM(tlog)(act: act.destruct())
	}
}

private func performSTM<A>(tlog : IORef<TransactionLog<A>>)(act : STMD<A>) -> IO<A> {
	switch act {
		case .Return(let a):
			return do_ { () -> A in
				commit(tlog)
				return a()
		}
		case .Retry:
			return waitForExternalRetry()
		case .NewTVar(_, let x, let cont):
			return do_ {
				let tv = !newTVarWithLog(tlog)(tvar: x)
				return performSTM(tlog)(act: (cont(!takeMVar((!takeMVar(tv.tvar)).globalContent))).destruct())
			}
		case .ReadTVar(let x, let cont):
			return do_ {
				let res : A = !readTVarWithLog(tlog)(v: x)
				return performSTM(tlog)(act: cont(res).destruct())
			}
		case .WriteTVar(let v, let x, let cont):
			return do_ {
				!writeTVarWithLog(tlog)(v: v)(x: x())
				return performSTM(tlog)(act: cont.destruct())
			}
		case .OrElse(let act1, let act2, let cont):
			return do_ {
				!orElseWithLog(tlog)
				let resl = !performOrElseLeft(tlog)(act: act1.destruct())
				switch resl {
					case .Some(let a):
						return performSTM(tlog)(act: cont(a).destruct())
					case .None:
						return do_ {
							!orRetryWithLog(tlog)
							return performSTM(tlog)(act: act2.bind(cont).destruct())
						}
				}
			}
	}
}

private func performOrElseLeft<A>(tlog : IORef<TransactionLog<A>>)(act : STMD<A>) -> IO<Optional<A>> {
	switch act {
		case .Return(let a):
			return do_ { () -> Optional<A> in
				return .Some(a())
			}
		case .Retry:
			return do_ { () -> Optional<A> in
					return .None
			}
		case .NewTVar(_, let x, let cont):
			return do_ {
				let tv = !newTVarWithLog(tlog)(tvar: x)
				return performOrElseLeft(tlog)(act: (cont(!takeMVar((!takeMVar(tv.tvar)).globalContent))).destruct())
			}
		case .ReadTVar(let x, let cont):
			return do_ {
				let res : A = !readTVarWithLog(tlog)(v: x)
				return performOrElseLeft(tlog)(act: cont(res).destruct())
			}
		case .WriteTVar(let v, let x, let cont):
			return do_ {
				!writeTVarWithLog(tlog)(v: v)(x: x())
				return performOrElseLeft(tlog)(act: cont.destruct())
			}
		case .OrElse(let act1, let act2, let cont):
			return do_ { () -> IO<Optional<A>> in
				!orElseWithLog(tlog)
				let resl = !performOrElseLeft(tlog)(act: act1.destruct())
				switch resl {
					case .Some(let x):
						return do_ { () -> IO<Optional<A>> in
							return performOrElseLeft(tlog)(act: cont(x).destruct())
						}
					case .None:
						return do_ {
							!orRetryWithLog(tlog)
							return performOrElseLeft(tlog)(act: act2.bind(cont).destruct())
						}
				}
			}
	}
}

func waitForExternalRetry<A>() -> IO<A> {
	return do_ {
		return undefined()
	}
}

