//
//  Actor.swift
//  Parallel-iOS
//
//  Created by Robert Widmann on 9/25/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Basis

public class Actor<M> : K1<M> {
	let pid : ThreadID
	let mbox : TChan<M>

	init(_ pid : ThreadID, _ mbox : TChan<M>) {
		self.pid = pid
		self.mbox = mbox
	}
}

extension Actor : Equatable {}

public func ==<M>(lhs: Actor<M>, rhs: Actor<M>) -> Bool {
	return lhs.pid == rhs.pid
}

extension Actor : Comparable {}

public func <=<M>(lhs: Actor<M>, rhs: Actor<M>) -> Bool {
	return lhs.pid <= rhs.pid
}

public func >=<M>(lhs: Actor<M>, rhs: Actor<M>) -> Bool {
	return lhs.pid >= rhs.pid
}

public func <<M>(lhs: Actor<M>, rhs: Actor<M>) -> Bool {
	return lhs.pid < rhs.pid
}

public func ><M>(lhs: Actor<M>, rhs: Actor<M>) -> Bool {
	return lhs.pid > rhs.pid
}

public func newActor<A, M>(i : A) -> (A -> TChan<M> -> IO<A>) -> IO<Actor<M>> {
	return { f in
		do_ { () -> Actor<M> in
			let m : TChan<M> = !newTChanIO()
			let p = !forkIO(f(i)(m) >> IO.pure(()))
			return Actor(p, m)
		}
	}
}

public func send<M>(a : Actor<M>) -> M -> IO<M> {
	return { m in atomically(writeTChan(a.mbox)(m)) >> IO.pure(m) }
}

//public func recieve<M, A, B>(mb : TChan<M>) -> (M -> IO<A>) -> IO<B> {
//	return { f in atomically(readTChan(mb)).bind(f) }
//}
