//
//  TChan.swift
//  Parallel-iOS
//
//  Created by Robert Widmann on 9/28/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Swiftz

/// `TChan` is a Transactional Channel.  Unlike regular Chans, modifications to the Channel must
/// take place as transactions in the STM Monad.
public struct TChan<A> {
	let readHead : TVar<TVar<TList<A>>>
	let writeHead : TVar<TVar<TList<A>>>

	private init(_ readHead : TVar<TVar<TList<A>>>, _ writeHead : TVar<TVar<TList<A>>>) {
		self.readHead = readHead
		self.writeHead = writeHead
	}
	
	public init() {
		let hole : TVar<TList<A>> = TVar(TList.TNil)
		let read = TVar(hole)
		let write = TVar(hole)
		self = TChan(read, write)
	}

	/// Returns a transaction that writes a value to the channel.
	public func write(x : A) -> STM<()> {
		return do_ { () -> () in
			let l = !self.writeHead.read()
			let nl : TVar<TList<A>> = !newTVar(TList.TNil)
			l.write(TList.TCons(x, nl))
			self.writeHead.write(nl)
		}
	}

	/// Returns a transaction that reads a value from the channel.  
	///
	/// If the channel is empty the transaction is retried until such time as it becomes full again.
	public func read() -> STM<A> {
		return do_ {
			let hd = !self.readHead.read()
			let lst = !hd.read()
			switch lst {
			case .TNil:
				return retry()
			case .TCons(let x, let xs):
				return do_ { () -> A in
					!self.readHead.write(xs)
					return x
				}
			}
		}
	}

	/// Returns a transaction that reads a value from the channel.  If the channel is empty the
	/// transaction will return .None, else .Some(val).
	public func tryRead() -> STM<Optional<A>> {
		return do_ { () -> STM<Optional<A>> in
			let hd = !self.readHead.read()
			let lst = !hd.read()
			switch lst {
			case .TNil:
				return do_ { () in .None }
			case .TCons(let x, let xs):
				return do_ { () -> Optional<A> in
					self.readHead.write(xs)
					return .Some(x)
				}
			}
		}
	}

	/// Returns a transaction that reads a value from the channel without dequeueing it.
	///
	/// If the channel is empty the transaction is retried until such time as it becomes full again.
	public func peek() -> STM<A> {
		return do_ { () -> STM<A> in
			let hd = !self.readHead.read()
			let lst = !hd.read()
			switch lst {
			case .TNil:
				return retry()
			case .TCons(let x, let xs):
				return do_ { () in x }
			}
		}
	}

	/// Returns a transaction that reads a value from the channel without dequeueing it..  If the 
	/// channel is empty the transaction will return .None, else .Some(val).
	public func tryPeek() -> STM<Optional<A>> {
		return do_ { () -> Optional<A> in
			let hd = !self.readHead.read()
			let lst = !hd.read()
			switch lst {
			case .TNil:
				return .None
			case .TCons(let x, let xs):
				return .Some(x)
			}
		}
	}

	/// Returns a transaction that duplicates a channel.
	///
	/// The duplicate channel begins empty, but data written to either channel from then on will be
	/// available from both. Because both channels share the same write end, data inserted into one
	/// channel may be read by both channels.
	public func duplicate() -> STM<TChan<A>> {
		return do_ { () -> TChan<A> in
			let hd = !self.writeHead.read()
			let newread = !newTVar(hd)
			return TChan(newread, self.writeHead)
		}
	}

	/// Returns a transaction that puts a data item back onto a channel, where it will be the next 
	/// item read.
	public func unGet(x : A) -> STM<()> {
		return do_ {
			let hd = !self.readHead.read()
			let newhd = !newTVar(TList.TCons(x, hd))
			return self.readHead.write(newhd)
		}
	}

	/// Returns a transaction that returns whether the channel is empty.
	public func isEmpty() -> STM<Bool> {
		return do_ { () -> Bool in
			let hd = !self.readHead.read()
			let lst = !hd.read()
			switch lst {
			case .TNil:
				return true
			case .TCons(_, _):
				return false
			}
		}
	}

	/// Returns a transaction that clones a channel.
	///
	/// Much like a duplicated channel, writes to the cloned channel are seen by the original.  
	/// Unlike duplicate, the cloned channel begins with the same content as the original.
	public func clone() -> STM<TChan<A>> {
		return do_ { () -> TChan<A> in
			let hd = !self.readHead.read()
			let newread = !newTVar(hd)
			return TChan(newread, self.writeHead)
		}
	}
}

public func newTChan<A>() -> STM<TChan<A>> {
	return do_ { () -> TChan<A> in
		let hole : TVar<TList<A>> = !newTVar(TList.TNil)
		let read = !newTVar(hole)
		let write = !newTVar(hole)
		return TChan(read, write)
	}
}

public func newBroadcastTChan<A>() -> STM<TChan<A>> {
	return do_ { () -> TChan<A> in
		let hole : TVar<TList<A>> = !newTVar(TList.TNil)
		let read : TVar<TVar<TList<A>>> = !newTVar(error(""))
		let write = !newTVar(hole)
		return TChan(read, write)
	}
}

public func newBroadcastTChanIO<A>() -> TChan<A> {
	let hole : TVar<TList<A>> = TVar(TList.TNil)
	let read : TVar<TVar<TList<A>>> = TVar(error(""))
	let write = TVar(hole)
	return TChan(read, write)
}


internal enum TList<A> {
	case TNil
	case TCons(A, TVar<TList<A>>)
}


