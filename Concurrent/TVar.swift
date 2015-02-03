//
//  TVar.swift
//  Parallel-iOS
//
//  Created by Robert Widmann on 9/28/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Swiftx

public protocol TVarType {
	typealias A
	var tvar : MVar<ITVar<A>> { get }
}

public struct TVar<A> : TVarType {
	public let tvar : MVar<ITVar<A>>
	let id : TVarId

	init(_ tvar : MVar<ITVar<A>>, _ id : TVarId) {
		self.tvar = tvar
		self.id = id
	}
}

public func newTVar<A>(x : A) -> STM<TVar<A>> {
	let mid = pthread_self()
	let tvar_id = !nextCounter()

	let content_global = !newMVar(x)
	let pointer_local_content = !newIORef([x])
	let mp = insert(mid)(pointer_local_content)(empty() as Map<ThreadID, IORef<[A]>>)
	let content_local = !newMVar(mp)
	let notify_list : MVar<Set<ThreadID>> = !newMVar(empty())
	let unset_lock : MVar<ThreadID> = !newEmptyMVar()

	let content_waiting_queue = !newMVar([] as [MVar<()>])
	let content_tvarx = !newMVar(ITVar(content_global, content_local, notify_list, unset_lock, waitingQueue: content_waiting_queue))

	let tvar = TVar<A>(content_tvarx, tvar_id)
	return STM(STMD.NewTVar(x, tvar, { (let y : A) in STM.pure(y) })) >> STM<TVar<A>>.pure(tvar)
}

public func readTVar<A>(v : TVar<A>) -> STM<A> {
	return STM<A>(STMD<A>.ReadTVar(v, { y in STM.pure(y) }))
}

public func writeTVar<A>(v : TVar<A>)(x : A) -> STM<()> {
	return STM<A>(STMD<A>.WriteTVar(v, x, STM<A>.pure(x))) >> STM<()>.pure(())
}


typealias TVarId = Int

extension TVar : Equatable { }
extension TVar : Comparable { }

public func ==<A>(lhs: TVar<A>, rhs: TVar<A>) -> Bool {
	return lhs.id == rhs.id
}

public func <=<A>(lhs: TVar<A>, rhs: TVar<A>) -> Bool { return lhs.id <= rhs.id }
public func >=<A>(lhs: TVar<A>, rhs: TVar<A>) -> Bool { return lhs.id >= rhs.id }
public func ><A>(lhs: TVar<A>, rhs: TVar<A>) -> Bool { return lhs.id > rhs.id }
public func <<A>(lhs: TVar<A>, rhs: TVar<A>) -> Bool { return lhs.id < rhs.id }

public struct ITVar<A> {
	let globalContent : MVar<A>
	let localContent  : MVar<Map<ThreadID, IORef<[A]>>>
	let notifyList    : MVar<Set<ThreadID>>
	let lock          : MVar<ThreadID>
	let waitingQueue  : MVar<[MVar<()>]>

	init (_ globalContent : MVar<A>, _ localContent : MVar<Map<ThreadID, IORef<[A]>>>, _ notifyList : MVar<Set<ThreadID>>, _ lock : MVar<ThreadID>, waitingQueue : MVar<[MVar<()>]>) {
		self.globalContent = globalContent
		self.localContent = localContent
		self.notifyList = notifyList
		self.lock = lock
		self.waitingQueue = waitingQueue
	}
}