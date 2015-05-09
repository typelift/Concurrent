//
//  Transactions.swift
//  Parallel-iOS
//
//  Created by Robert Widmann on 9/25/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Swiftz

/// Software Transaction Memory is a terribly tricky thing to do in a profoundly impure language,
/// but that never stopped me before...
///
/// This implementation of an STM transaction manager comes straight from
///
/// David Sabel, "A Haskell-Implementation of STM Haskell with Early Conflict Detection"
/// http://ceur-ws.org/Vol-1129/paper48.pdf
/// 
/// whose formalizations in Haskell were absolutely invaluable.  To that end, the implementation
/// matches the one described in the paper as much as possible with the exception of the existential
/// types hiding a lot of the plumbing.  While we don't get the proper benefits the paper outlines,
/// there is a bit of efficiency gained by de-duplicating all of the extra TVars it had lying around.
private let globalCounter : MVar<TVarId> = MVar(initial: 0)

internal func nextCounter() -> TVarId {
	return globalCounter.modify { i in
		return (i + 1, i)
	}
}

struct TransactionLog<A> {
	let readTVars : Set<TVar<A>>
	let tripleStack : [(Set<TVar<A>>, Set<TVar<A>>, Set<TVar<A>>)]
	let lockingSet : Set<TVar<A>>

	init(_ readTVars : Set<TVar<A>>, _ tripleStack : [(Set<TVar<A>>, Set<TVar<A>>, Set<TVar<A>>)], _ lockingSet : Set<TVar<A>>) {
		self.readTVars = readTVars
		self.tripleStack = tripleStack
		self.lockingSet = lockingSet
	}
}

func commit<A>(tlog : MVar<TransactionLog<A>>) {
	writeStartWithLog(tlog)
	writeClearWithLog(tlog)
	sendRetryWithLog(tlog)
	writeTVWithLog(tlog)
	writeTVnWithLog(tlog)
	writeEndWithLog(tlog)
	unlockTVWithLog(tlog)
}

func emptyTLOG<A>() -> MVar<TransactionLog<A>> {
	return MVar(initial: TransactionLog<A>(Set(), [(Set(), Set(), Set())], Set()))
}

func newTVarWithLog<A>(log : MVar<TransactionLog<A>>)(tvar : TVar<A>) -> TVar<A> {
	let lg = log.take()

	if lg.tripleStack.isEmpty {
		return error("")
	}
	
	let (la, ln, lw) = lg.tripleStack.first!
	
	let lg2 = TransactionLog(lg.readTVars, [(la.union([tvar]), ln.union([tvar]), lw)], lg.lockingSet)
	log.swap(lg2)
	return tvar
}

func readTVarWithLog<A>(log : MVar<TransactionLog<A>>)(v : TVar<A>) -> A {
	let res : Either<MVar<()>, A> = tryReadTvarWithLog(log)(ptvar: v)
	switch res {
		case .Right(let r):
			return r.value
		case .Left(let blockvar):
			blockvar.value.take()
			return readTVarWithLog(log)(v: v)
	}
}


func tryReadTvarWithLog<A>(log : MVar<TransactionLog<A>>)(ptvar : TVar<A>) -> Either<MVar<()>, A> {
	let _tva : ITVar<A> = ptvar.tvar.take()

	let lg = log.read()
	switch match(log.read().tripleStack) {
		case .Nil:
			return error("")
		case .Cons(let (la, ln, lw), let xs):
			if la.contains(ptvar) {
				let mid = pthread_self()
				let localmap = _tva.localContent.read()
				let lk = localmap[mid]!.read()
				ptvar.tvar.put(_tva)
				return Either.right(head(lk)!)
			} else {
				if _tva.lock.isEmpty {
					let mid = pthread_self()

					let nl = _tva.notifyList.take()
					_tva.notifyList.put(nl.union([mid]))
					let globalC = _tva.globalContent.read()
					let content_local = MVar<[A]>(initial: [globalC])

					let lg2 = TransactionLog(lg.readTVars.union([ptvar]), [(la.union([ptvar]), ln, lw)] + lg.tripleStack, lg.lockingSet)
					log.swap(lg2)
					
					var mp = _tva.localContent.take()
					mp[mid] = content_local
					_tva.localContent.put(mp)
					ptvar.tvar.put(_tva)
					return Either.right(globalC)
				} else {
					let blockvar : MVar<()> = MVar()
					let wq = _tva.waitingQueue.take()
					_tva.waitingQueue.put([blockvar] + wq)
					ptvar.tvar.put(_tva)
					return Either.left(blockvar)
				}
			}

	}
}

func writeTVarWithLog<A>(log : MVar<TransactionLog<A>>)(v : TVar<A>)(x : A) {
	let res : Either<MVar<()>, ()> = tryWriteTVarWithLog(log)(ptvar: v)(con: x)
	switch res {
	case .Right(_):
		return
	case .Left(let blockvar):
		blockvar.value.take()
		return writeTVarWithLog(log)(v: v)(x: x)
	}
}

func tryWriteTVarWithLog<A>(log : MVar<TransactionLog<A>>)(ptvar : TVar<A>)(con : A) -> Either<MVar<()>, ()> {
	let _tva : ITVar<A> = ptvar.tvar.take()
	let lg = log.read()
	let mid = pthread_self()

	switch match(lg.tripleStack) {
		case .Cons(let (la, ln, lw), let xs):
			if la.contains(ptvar) {
				let mid = pthread_self()
				let localmap = _tva.localContent.read()
				let oldContent = localmap[mid]!
				let lk = localmap[mid]!.read()
				oldContent.put([con] + tail(lk)!)

				let lg2 = TransactionLog<A>(lg.readTVars, [(la, ln, lw.union([ptvar]))] + xs, lg.lockingSet)
				log.swap(lg2)
				ptvar.tvar.put(_tva)
				return Either.right(())
			} else {
				if _tva.lock.isEmpty {
					let globalC = _tva.globalContent.read()
					let content_local = MVar<[A]>(initial: [con])
					
					var mp = _tva.localContent.take()
					mp[mid] = content_local
					_tva.localContent.put(mp)
					
					let lg2 = TransactionLog(lg.readTVars.union([ptvar]), [(la.union([ptvar]), ln, lw.union([ptvar]))] + xs, lg.lockingSet)
					log.swap(lg2)
					
					ptvar.tvar.put(_tva)
					return Either.right(())
				} else {
					let blockvar : MVar<()> = MVar()
					let wq = _tva.waitingQueue.take()
					_tva.waitingQueue.put([blockvar] + wq)
					ptvar.tvar.put(_tva)
					return Either.left(blockvar)
				}
			}
		default:
			return error("")
	}
}

func orRetryWithLog<A>(log : MVar<TransactionLog<A>>) {
	let lg = log.read()
	switch match(lg.tripleStack) {
		case .Nil:
			return error("")
		case .Cons(let (la, ln, lw), let xs):
			let mid = pthread_self()
			undoubleLocalTVars(mid)(l: [TVar<A>](la))
			log.swap(TransactionLog<A>(lg.readTVars, xs, lg.lockingSet))
	}
}

private func undoubleLocalTVars<A>(mid : ThreadID)(l : [TVar<A>]) {
	switch match(l) {
		case .Nil:
			return
		case .Cons(let tv, let xs):
			let _tvany : ITVar<A> = tv.tvar.take()
			let localmap = _tvany.localContent.read()
			switch localmap[mid] {
				case .None:
					return error("")
				case .Some(let conp):
					let l = conp.read()
					conp.put(tail(l)!)
					tv.tvar.put(_tvany)
					_tvany.localContent.put(localmap)
					return undoubleLocalTVars(mid)(l: xs)
			}

	}
}

func orElseWithLog<A>(log : MVar<TransactionLog<A>>) {
	let lg : TransactionLog<A> = log.read()
	let mid = pthread_self()
	switch match(lg.tripleStack) {
		case .Nil:
			return error("")
		case .Cons(let (la, ln, lw), let xs):
			doubleLocalTVars(mid)(l: [TVar<A>](la))
			log.swap(TransactionLog<A>(lg.readTVars, [(la, ln, lw)] + [(la, ln, lw)] + xs, lg.lockingSet))
	}
}

private func doubleLocalTVars<A>(mid : ThreadID)(l : [TVar<A>]) {
	switch match(l) {
		case .Nil:
			return
		case .Cons(let tv, let xs):
			let _tvany : ITVar<A> = tv.tvar.take()
			let localmap = _tvany.localContent.take()
			switch localmap[mid] {
				case .None:
					return
				case .Some(let conp):
					let lx : [A] = conp.read()
					conp.put([head(lx)!] + [head(lx)!] + tail(lx)!)
					_tvany.localContent.put(localmap)
					tv.tvar.put(_tvany)
					return doubleLocalTVars(mid)(l: xs)
			}
	}
}

private func _writeStartWithLog<A>(log : MVar<TransactionLog<A>>) -> Either<MVar<()>, ()> {
	let mid = pthread_self()
	let lg = log.read()
	switch match(lg.tripleStack) {
		case .Nil:
			return error("")
		case .Cons(let (la, ln, lw), _):
			let t = lg.readTVars
			let xs = t.union(la.subtract(ln))
			let held = sorted([TVar<A>](xs))
			let res : Either<MVar<()>, ()> = grabLocks(mid, held, [])
			switch res {
				case .Right(_):
					let lg2 = TransactionLog<A>(lg.readTVars, lg.tripleStack, xs)
					log.swap(lg2)
					return Either.right(())
				case .Left(let lock):
					return Either.left(lock.value)
			}
	}
}

private func grabLocks<A>(mid : ThreadID, list : [TVar<A>], held : [TVar<A>]) -> Either<MVar<()>, ()> {
	switch match(list) {
		case .Nil:
			return Either.right(())
		case .Cons(let ptvar, let xs):
			let mid = pthread_self()
			let _tvany : ITVar<A> = ptvar.tvar.take()
			if _tvany.lock.tryPut(mid) {
				ptvar.tvar.put(_tvany)
				return grabLocks(mid, tail(list)!, [ptvar] + held)
			} else {
				let waiton : MVar<()> = MVar()
				let l = _tvany.waitingQueue.take()
				_tvany.waitingQueue.put(l + [waiton])
				ptvar.tvar.put(_tvany)
				let _ = held.reverse().map { (let tva : TVar<A>) -> () in
					let _tv : ITVar<A> = tva.tvar.take()
					_tv.lock.take()
					tva.tvar.put(_tv)
					return ()
				}
				return Either.left(waiton)
			}
	}
}

func writeStartWithLog<A>(log : MVar<TransactionLog<A>>) {
	let res : Either<MVar<()>, ()> = _writeStartWithLog(log)
	switch res {
		case .Left(let lock):
			lock.value.take()
			yield()
			sleep(1000)
			writeStartWithLog(log)
		case .Right(_):
			return
	}
}

func writeClearWithLog<A>(log : MVar<TransactionLog<A>>) {
	let lg : TransactionLog<A> = log.read()
	let xs = [TVar<A>](lg.readTVars)
	iterateClearWithLog(log)(l: xs)
	log.swap(TransactionLog<A>(Set(), lg.tripleStack, lg.lockingSet))
}

private func iterateClearWithLog<A>(log : MVar<TransactionLog<A>>)(l: [TVar<A>]) {
	switch match(l) {
		case .Nil:
			return
		case .Cons(let tv, let xs):
			let mid = pthread_self()
			let _tvany : ITVar<A> = tv.tvar.take()
			let nl = _tvany.notifyList.take()

			_tvany.notifyList.put(nl.subtract([mid]))
			tv.tvar.put(_tvany)
			iterateClearWithLog(log)(l: xs)
	}
}

func notify(l : [ThreadID]) {
	switch match(l) {
		case .Nil:
			return
		case .Cons(let tid, let xs):
//				throwTo(tid)(RetryException())
			return notify(xs)
	}
}

func sendRetryWithLog<A>(log : MVar<TransactionLog<A>>) {
	let lg : TransactionLog<A> = log.read()
	let mid = pthread_self()
	switch match(lg.tripleStack) {
		case .Nil:
			return error("")
		case .Cons(let (la, ln, lw), let xs):
			let openLW : [ThreadID] = getIDs([TVar<A>](lw))(ls: Set())
			return notify(openLW)
	}
}

private func getIDs<A>(l : [TVar<A>])(ls : Set<ThreadID>) -> [ThreadID] {
	switch match(l) {
		case .Nil:
			return [ThreadID](ls)
		case .Cons(let tv, let xs):
			let mid = pthread_self()
			let _tvany : ITVar<A> = tv.tvar.take()
			let l = _tvany.notifyList.take()
			_tvany.notifyList.put(Set())
			tv.tvar.put(_tvany)
			return getIDs(xs)(ls: l.union(ls))
	}
}

func writeTVWithLog<A>(log : MVar<TransactionLog<A>>) {
	let lg : TransactionLog<A> = log.read()
	let mid = pthread_self()
	switch match(lg.tripleStack) {
		case .Nil:
			return error("")
		case .Cons(let (la, ln, lw), let xs):
			let tobewritten = lw.subtract(ln)
			writeTVars([TVar<A>](tobewritten))
			log.swap(TransactionLog<A>(lg.readTVars, [(la, ln, Set())] + xs, lg.lockingSet))
	}
}

private func writeTVars<A>(l : [TVar<A>]) {
	switch match(l) {
		case .Nil:
			return
		case .Cons(let tv, let xs):
			let mid = pthread_self()
			let _tvany : ITVar<A> = tv.tvar.take()
			let localmap = _tvany.localContent.take()
			switch localmap[mid] {
				case .None:
					return error("")
				case .Some(let conp):
					let con : [A] = conp.read()
					var map = localmap
					map.removeValueForKey(mid)
					_tvany.localContent.put(map)
					_tvany.globalContent.take()
					_tvany.globalContent.put(head(con)!)
					tv.tvar.put(_tvany)
					return writeTVars(xs)
			}
	}
}

func writeTVnWithLog<A>(log : MVar<TransactionLog<A>>) {
	let lg : TransactionLog<A> = log.read()
	let mid = pthread_self()
	switch match(lg.tripleStack) {
		case .Nil:
			return error("")
		case .Cons(let (la, ln, lw), let xs):
			let t = lg.readTVars
			let k = lg.lockingSet
			let toBeWritten = [TVar<A>](ln)
			writeNew(toBeWritten)
			log.swap(TransactionLog<A>(lg.readTVars, [(la, Set(), lw)] + xs, lg.lockingSet))
	}
}

private func writeNew<A>(l : [TVar<A>]) {
	switch match(l) {
		case .Nil:
			return
		case .Cons(let tv, let xs):
			let mid = pthread_self()
			let _tvany : ITVar<A> = tv.tvar.take()
			let limap = _tvany.localContent.take()
			var lmap = limap
			lmap.removeValueForKey(mid)
			if lmap.isEmpty {
				switch lmap[mid] {
					case .None:
						return error("")
					case .Some(let conp):
						let con : [A] = conp.read()

						_tvany.globalContent.take()
						_tvany.globalContent.put(head(con)!)
						_tvany.localContent.put(Dictionary())
						tv.tvar.put(_tvany)
						return writeNew(xs)
				}
			}
			return error("")
	}
}

func writeEndWithLog<A>(log : MVar<TransactionLog<A>>) {
	let lg : TransactionLog<A> = log.read()
	let mid = pthread_self()
	switch match(lg.tripleStack) {
		case .Nil:
			return error("")
		case .Cons(let (la, ln, lw), let xs):
			let l = lg.readTVars
			let k = lg.lockingSet
			return clearEntries([TVar<A>](la))
	}
}

func clearEntries<A>(l : [TVar<A>]) {
	switch match(l) {
		case .Nil:
			return
		case .Cons(let tv, let xs):
			let mid = pthread_self()
			let _tvany : ITVar<A> = tv.tvar.take()
			let localmapi = _tvany.localContent.take()
			var localmap = localmapi
			localmap.removeValueForKey(mid)
			_tvany.localContent.put(localmap)
			return tv.tvar.put(_tvany)
	}
}

func unlockTVWithLog<A>(log : MVar<TransactionLog<A>>) {
	let lg : TransactionLog<A> = log.read()
	let mid = pthread_self()
	switch match(lg.tripleStack) {
		case .Nil:
			return error("")
		case .Cons(let (la, ln, lw), let xs):
			let k = lg.lockingSet
			unlockTVars([TVar<A>](k))
			log.swap(TransactionLog<A>(lg.readTVars, lg.tripleStack, Set()))
	}
}

func unlockTVars<A>(l : [TVar<A>]) {
	switch match(l) {
		case .Nil:
			return 
		case .Cons(let tv, let xs):
			let _tvany : ITVar<A> = tv.tvar.take()
			let wq = _tvany.waitingQueue.take()
			_tvany.lock.take()
			let _ = wq.map({ mv in 
				mv.put(()) 
			})
			return tv.tvar.put(_tvany)
	}
}

