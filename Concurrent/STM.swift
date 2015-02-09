//
//  STM.swift
//  Basis
//
//  Created by Robert Widmann on 9/15/14.
//  Copyright (c) 2014 Robert Widmann. All rights reserved.
//

import Swiftz

public struct STM<A> {
	typealias B = Any

	let act : () -> STMD<A>


	init(_ act : @autoclosure () -> STMD<A>) {
		self.act = act
	}
	
	public func then<B>(next : STM<B>) -> STM<B> {
		return self.bind({ (_) in
			return next
		})
	}
}

extension STM : Functor {
	typealias FA = STM<A>

	public func fmap<B>(f : A -> B) -> STM<B> {
		return self >>- { y in STM<B>.pure(f(y)) }
	}
}

public func <^> <A, B>(f : A -> B, io : STM<A>) -> STM<B> {
	return io.fmap(f)
}

//public func <^ <A, B>(x : A, io : STM<B>) -> STM<A> {
//	return STM.fmap(const(x))(io)
//}

extension STM : Applicative {
	public static func pure(a : A) -> STM<A> {
		return STM<A>(STMD<A>.Return(a))
	}
	
	public func ap<B>(fn : STM<A -> B>) -> STM<B> {
		return !fn <^> self
	}
}

public func <*> <A, B>(fn : STM<A -> B>, m: STM<A>) -> STM<B> {
	return !fn <^> m
}

//public func *> <A, B>(a : STM<A>, b : STM<B>) -> STM<B> {
//	return const(identity) <^> a <*> b
//}
//
//public func <* <A, B>(a : STM<A>, b : STM<B>) -> STM<A> {
//	return const <^> a <*> b
//}

extension STM : Monad {
	public func bind<B>(f : A -> STM<B>) -> STM<B> {
		return STM<B>(self.act().bind({ a in f(a).act() }))
	}
}


public func >>- <A, B>(x: STM<A>, f: A -> STM<B>) -> STM<B> {
	return x.bind(f)
}

public prefix func !<A>(stm: STM<A>) -> A {
	return atomically(stm)
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
				return cont(x()).act().bind(f)
			case .ReadTVar(let x, let cont):
				return STM<B>(cont(x.tvar.read().globalContent.read()).act().bind(f)).act()
			case .WriteTVar(let v, let x, let cont):
				return cont.act().bind({ _ in f(v.tvar.read().globalContent.read()) })
			case .OrElse(let a1, let a2, let cont):
				return a1.act().bind({ i in cont(i).act().bind(f) })
		}
	}
}

public func orElse<A>(a1 : STM<A>)(a2 : STM<A>) -> STM<A> {
	return STM(STMD<A>.OrElse(a1, a2, { x in STM(STMD.Return(x)) }))
}

public func retry<A>() -> STM<A> {
	return STM(STMD<A>.Retry)
}

public func newTVarIO<A>(x : A) -> TVar<A> {
	return atomically(newTVar(x))
}

public func atomically<A>(act : STM<A>) -> A {
	let tlog : MVar<TransactionLog<A>> = emptyTLOG()
	return performSTM(tlog)(act: act.act())
}

private func performSTM<A>(tlog : MVar<TransactionLog<A>>)(act : STMD<A>) -> A {
	switch act {
		case .Return(let a):
			commit(tlog)
			return a()
		case .Retry:
			return waitForExternalRetry()
		case .NewTVar(_, let x, let cont):
			let tv = newTVarWithLog(tlog)(tvar: x)
			return performSTM(tlog)(act: (cont(tv.tvar.take().globalContent.take()).act()))
		case .ReadTVar(let x, let cont):
			let res : A = readTVarWithLog(tlog)(v: x)
			return performSTM(tlog)(act: cont(res).act())
		case .WriteTVar(let v, let x, let cont):
			writeTVarWithLog(tlog)(v: v)(x: x())
			return performSTM(tlog)(act: cont.act())
		case .OrElse(let act1, let act2, let cont):
			orElseWithLog(tlog)
			let resl = performOrElseLeft(tlog)(act: act1.act())
			switch resl {
				case .Some(let a):
					return performSTM(tlog)(act: cont(a).act())
				case .None:
					orRetryWithLog(tlog)
					return performSTM(tlog)(act: act2.bind(cont).act())
			}
	}
}

private func performOrElseLeft<A>(tlog : MVar<TransactionLog<A>>)(act : STMD<A>) -> Optional<A> {
	switch act {
		case .Return(let a):
			return .Some(a())
		case .Retry:
				return .None
		case .NewTVar(_, let x, let cont):
			let tv = newTVarWithLog(tlog)(tvar: x)
			return performOrElseLeft(tlog)(act: cont(tv.tvar.take().globalContent.take()).act())
		case .ReadTVar(let x, let cont):
			let res : A = readTVarWithLog(tlog)(v: x)
			return performOrElseLeft(tlog)(act: cont(res).act())
		case .WriteTVar(let v, let x, let cont):
			writeTVarWithLog(tlog)(v: v)(x: x())
			return performOrElseLeft(tlog)(act: cont.act())
		case .OrElse(let act1, let act2, let cont):
			orElseWithLog(tlog)
			let resl = performOrElseLeft(tlog)(act: act1.act())
			switch resl {
				case .Some(let x):
					return performOrElseLeft(tlog)(act: cont(x).act())
				case .None:
					orRetryWithLog(tlog)
					return performOrElseLeft(tlog)(act: act2.bind(cont).act())
			}
	}
}

func waitForExternalRetry<A>() -> A {
	return undefined()
}

