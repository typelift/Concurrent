//
//  TChan.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//

private indirect enum TList<A> {
	case TNil
	case TCons(A, TVar<TList<A>>)
}

/// Transactional Channels are unbounded FIFO streams of values with a read and write terminals comprised of
/// TVars.
public struct TChan<A> {
	private let readHead : TVar<TVar<TList<A>>>
	private let writeHead : TVar<TVar<TList<A>>>

	private init(_ readHead : TVar<TVar<TList<A>>>, _ writeHead : TVar<TVar<TList<A>>>) {
		self.readHead = readHead
		self.writeHead = writeHead
	}

	/// Creates and returns a new empty channel.
	public init() {
		let hole : TVar<TList<A>> = TVar(TList.TNil)
		let read = TVar(hole)
		let write = TVar(hole)
		self = TChan(read, write)
	}
	
	/// Creates and returns a new write-only channel.
	///
	/// To read from a broadcast transactional channel, `duplicate()` it first.
	public init(forBroadcast: ()) {
		let hole : TVar<TList<A>> = TVar(TList.TNil)
		let read : TVar<TVar<TList<A>>> = TVar(undefined())
		let write = TVar(hole)
		self = TChan(read, write)
	}
	
	/// Uses an STM transaction to atomically create and return a new empty channel.
	public func newTChan() -> STM<TChan<A>> {
		let hole : TVar<TList<A>> = TVar(TList.TNil)
		let read = TVar(hole)
		let write = TVar(hole)
		return STM<TChan<A>>.pure(TChan(read, write))
	}
	
	/// Uses an STM transaction to atomically create and return a new write-only channel.
	///
	/// To read from a broadcast transactional channel, `duplicate()` it first. 
	public func newBroadcastTChan() -> STM<TChan<A>> {
		let hole : TVar<TList<A>> = TVar(TList.TNil)
		let read : TVar<TVar<TList<A>>> = TVar(undefined())
		let write = TVar(hole)
		return STM<TChan<A>>.pure(TChan(read, write))
	}
	
	/// Uses an STM transaction to atomically write a value to a channel.
	public func write(val : A) -> STM<()> {
		return self.writeHead.read().flatMap { l in
			let nl : TVar<TList<A>> = TVar(TList.TNil)
			return l.write(TList.TCons(val, nl)).then(self.writeHead.write(nl))
		}
	}
	
	/// Uses an STM transaction to atomically read a value from the channel.
	public func read() -> STM<A> {
		return self.readHead.read().flatMap { hd in
			return hd.read().flatMap { lst in
				switch lst {
				case .TNil:
					return STM.retry()
				case .TCons(let x, let xs):
					return self.readHead.write(xs).then(STM<A>.pure(x))
				}
			}
		}
	}
	
	/// Uses an STM transaction to atomically read a value from the channel
	/// without retrying on failure.
	public func tryRead() -> STM<Optional<A>> {
		return self.readHead.read().flatMap { hd in
			return hd.read().flatMap { lst in
				switch lst {
				case .TNil:
					return STM<Optional<A>>.pure(nil)
				case .TCons(let x, let xs):
					return self.readHead.write(xs).then(STM<Optional<A>>.pure(.Some(x)))
				}
			}
		}
	}
	
	/// Uses an STM transaction to atomically get the next value from the 
	/// channel, retrying on failure.
	public func peek() -> STM<A> {
		return self.readHead.read().flatMap { hd in
			return hd.read().flatMap { lst in
				switch lst {
				case .TNil:
					return STM.retry()
				case .TCons(let x, _):
					return STM<A>.pure(x)
				}
			}
		}
	}
	
	/// Uses an STM transaction to atomically get the next value from the 
	/// channel without retrying.
	public func tryPeek() -> STM<Optional<A>> {
		return self.readHead.read().flatMap { hd in
			return hd.read().flatMap { lst in
				switch lst {
				case .TNil:
					return STM<Optional<A>>.pure(.None)
				case .TCons(let x, _):
					return STM<Optional<A>>.pure(.Some(x))
				}
			}
		}
	}
	
	/// Uses an STM transaction to atomically duplicate a channel.
	///
	/// The duplicate channel begins empty, but data written to either channel
	/// from then on will be available from both. Hence this creates a kind of
	/// broadcast channel, where data written by anyone is seen by everyone else.
	public func duplicate() -> STM<TChan<A>> {
		return self.writeHead.read().flatMap { hd in
			let newread = TVar(hd)
			return STM<TChan<A>>.pure(TChan(newread, self.writeHead))
		}
	}
	
	/// Uses an STM transaction to atomically put a data item back onto a 
	/// channel, where it will be the next item read.
	public func unGet(x : A) -> STM<()> {
		return self.readHead.read().flatMap { hd in
			let newhd = TVar(TList.TCons(x, hd))
			return self.readHead.write(newhd)
		}
	}
	
	/// Uses an STM transaction to return whether the channel is empty.
	public var isEmpty : STM<Bool> {
		return self.readHead.read().flatMap { hd in
			return hd.read().flatMap { lst in
				switch lst {
				case .TNil:
					return STM<Bool>.pure(true)
				case .TCons(_, _):
					return STM<Bool>.pure(false)
				}
			}
		}
	}
	
	/// Uses an STM transaction to atomically clone a channel.
	///
	/// Similar to `duplicate()`, but the cloned channel starts with the same
	/// content available as the original channel.
	public func clone() -> STM<TChan<A>> {
		return self.readHead.read().flatMap { hd in
			let newread = TVar(hd)
			return STM<TChan<A>>.pure(TChan(newread, self.writeHead))
		}
	}
}

private func undefined<A>() -> A {
	fatalError("")
}
