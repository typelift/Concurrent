//
//  TQueue.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//

public struct TQueue<A> {
	let readEnd : TVar<[A]>
	let writeEnd : TVar<[A]>

	private init(_ readEnd : TVar<[A]>, _ writeEnd : TVar<[A]>) {
		self.readEnd = readEnd
		self.writeEnd = writeEnd
	}
	
	public func create() -> STM<TQueue<A>> {
		let read = TVar([] as [A])
		let write = TVar([] as [A])
		return STM<TQueue<A>>.pure(TQueue(read, write))
	}

	/// Uses an atomic transaction to write the given value to the receiver.
	///
	/// Blocks if the queue is full.
	public func write(val : A) -> STM<()> {
		return self.writeEnd.read().flatMap { list in
			return self.writeEnd.write([val] + list)
		}
	}

	/// Uses an atomic transaction to read the next value from the receiver.
	public func read() -> STM<A> {
		return self.readEnd.read().flatMap { xs in
			if let x = xs.first {
				return self.readEnd.write(Array(xs.dropFirst()))
					.then(STM<A>.pure(x))
			}
			return self.writeEnd.read().flatMap { ys in
				if ys.isEmpty {
					return STM<A>.retry()
				}
				let zs = ys.reverse()
				if let z = zs.first {
					return self.writeEnd.write([]).then(self.readEnd.write(Array(zs.dropFirst()))).then(STM<A>.pure(z))
				}
				fatalError()
			}
		}
	}
	
	/// Uses an atomic transaction to read the next value from the receiver
	/// without blocking or retrying on failure.
	public func tryRead() -> STM<Optional<A>> {
		return self.read().fmap(Optional.Some).orElse(STM<A?>.pure(.None))
	}

	/// Uses an atomic transaction to get the next value from the receiver
	/// without removing it, retrying if the queue is empty.
	public func peek() -> STM<A> {
		return self.read().flatMap { x in
			return self.unGet(x).then(STM<A>.pure(x))
		}
	}

	/// Uses an atomic transaction to get the next value from the receiver
	/// without removing it without retrying if the queue is empty.
	public func tryPeek() -> STM<Optional<A>> {
		return self.tryRead().flatMap { m in
			switch m {
			case let .Some(x):
				return self.unGet(x).then(STM<A?>.pure(m))
			case .None:
				return STM<A?>.pure(.None)
			}
		}
	}

	/// Uses an atomic transaction to put a data item back onto a channel where
	/// it will be the next item read.
	///
	/// Blocks if the queue is full.
	public func unGet(x : A) -> STM<()> {
		return self.readEnd.read().flatMap { xs in
			return self.readEnd.write([x] + xs)
		}
	}

	/// Uses an STM transaction to return whether the channel is empty.
	public var isEmpty : STM<Bool> {
		return self.readEnd.read().flatMap { xs in
			if xs.isEmpty {
				return self.writeEnd.read().flatMap { ys in
					return STM<Bool>.pure(ys.isEmpty)
				}
			}
			return STM<Bool>.pure(false)
		}
	}
}
