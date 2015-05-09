//
//  TVar.swift
//  Parallel-iOS
//
//  Created by Robert Widmann on 9/28/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Swiftz

public struct TVar<A> : Hashable {
	public let tvar : MVar<ITVar<A>>
	let id : TVarId

	init(_ tvar : MVar<ITVar<A>>, _ id : TVarId) {
		self.tvar = tvar
		self.id = id
	}
	
	public init(_ x : A) {
		self = atomically(newTVar(x))
	}
	
	public var hashValue : Int { 
		return self.id 
	}
	
	public func read() -> STM<A> {
		return STM<A>(STMD<A>.ReadTVar(self, { y in STM.pure(y) }))
	}
	
	public func write(x : A) -> STM<()> {
		return STM<A>(STMD<A>.WriteTVar(self, { x }, STM<A>.pure(x))).then(STM<()>.pure(()))
	}
}

public func newTVar<A>(x : A) -> STM<TVar<A>> {
	let mid = pthread_self()
	let tvar_id = nextCounter()

	let content_global = MVar(initial: x)
	let pointer_local_content = MVar(initial: [x])
	let mp = [mid: pointer_local_content]
	let content_local = MVar(initial: mp)
	let notify_list : MVar<Set<ThreadID>> = MVar(initial: Set())
	let unset_lock : MVar<ThreadID> = MVar()

	let content_waiting_queue = MVar(initial: [] as [MVar<()>])
	let content_tvarx = MVar(initial: ITVar(content_global, content_local, notify_list, unset_lock, waitingQueue: content_waiting_queue))

	let tvar = TVar<A>(content_tvarx, tvar_id)
	return STM(STMD.NewTVar({ x }, tvar, { (let y : A) in STM.pure(y) })).then(STM<TVar<A>>.pure(tvar))
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
	let localContent  : MVar<Dictionary<ThreadID, MVar<[A]>>>
	let notifyList    : MVar<Set<ThreadID>>
	let lock          : MVar<ThreadID>
	let waitingQueue  : MVar<[MVar<()>]>

	init (_ globalContent : MVar<A>, _ localContent : MVar<Dictionary<ThreadID, MVar<[A]>>>, _ notifyList : MVar<Set<ThreadID>>, _ lock : MVar<ThreadID>, waitingQueue : MVar<[MVar<()>]>) {
		self.globalContent = globalContent
		self.localContent = localContent
		self.notifyList = notifyList
		self.lock = lock
		self.waitingQueue = waitingQueue
	}
}