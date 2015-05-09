//
//  TQueue.swift
//  Parallel-iOS
//
//  Created by Robert Widmann on 9/28/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Swiftz

/// A TQueue acts like a TChan but with faster throughput at the cost of removing duplication
/// operations.
public struct TQueue<A> {
	let readEnd : TVar<[A]>
	let writeEnd : TVar<[A]>

	init(_ readEnd : TVar<[A]>, _ writeEnd : TVar<[A]>) {
		self.readEnd = readEnd
		self.writeEnd = writeEnd
	}

	/// Returns an operation that writes a value into the TQueue.
	public func write(x : A) -> STM<()> {
		return self.writeEnd.modify { [x] + $0 }
	}

	/// Returns an operation that reads a value from the TQueue.
	///
	/// The TQueue will attempts to read first from its read head.  If no values are found there it
	/// will check its write head.  If there are still no values to be found, the operation will
	/// block retrying.
	public func read() -> STM<A> {
		return do_ { () -> STM<A> in
			let end = !self.readEnd.read()
			switch match(end) {
			case .Nil: // If there is nothing to be had on the read head, check the write head.
				let ys = !self.writeEnd.read()
				switch match(ys.reverse()) {
				case .Nil: // Still nothing, spin.
					return retry()
				case let .Cons(z, zs): // Found something.  Empty the write head return its tail.
					return do_ {
						self.writeEnd.write([])
						self.readEnd.write(zs)
						return STM.pure(z)
					}
				}
			case let .Cons(x, xs): // Found something, return the head of the read end.
				return do_ {
					self.readEnd.write(xs)
					return STM.pure(x)
				}
			}
		}
	}

	/// Returns an operation that gets the next value from the TQueue without removing it.
	///
	/// If no value is found, the operation will block retrying.
	public func peek() -> STM<A> {
		return do_ { () -> A in
			let x = !self.read()
			self.unGet(x)
			return x
		}
	}

	/// Returns an operation that attempts to read from the TQueue.  
	///
	/// If the TQueue contains no values the result of the operation is .None, else it is the first
	/// value in the read head in a .Some.
	public func tryRead() -> STM<Optional<A>> {
		return orElse(self.read().fmap { .Some($0) })(second: STM.pure(.None))
	}

	/// Returns an operation that attempts to get the next value from the TQueue without removing it.
	///
	/// If the TQueue contains no values the reuslt of the operation is .None, else it is the first
	/// value in the read head in a .Some.
	public func tryPeek() -> STM<Optional<A>> {
		return do_ {
			let m = !self.tryRead()
			switch m {
			case .None:
				return STM.pure(m)
			case let .Some(x):
				return do_ {
					self.unGet(x)
					return STM.pure(m)
				}
			}
		}
	}

	/// Returns an operation that puts a value back into the TQueue where it will be the first value
	/// returned from the next read.
	public func unGet(x : A) -> STM<()> {
		return self.readEnd.modify { [x] + $0 }
	}

	/// Returns true if the TQueue is empty, else false.
	///
	/// The TQueue will first check emptiness using its read head, then its write head.  The value
	/// of this function may be misleading in the middle of a large computation and should only be
	/// considered a snapshot in time.
	public func isEmpty() -> STM<Bool> {
		return do_ {
			switch match(!self.readEnd.read()) {
			case .Cons(_, _):
				return STM.pure(false)
			case .Nil:
				return do_ {
					switch match(!self.writeEnd.read()) {
					case .Nil:
						return STM.pure(true)
					default:
						return STM.pure(false)
					}
				}
			}
		}
	}
}

public func newTQueue<A>() -> STM<TQueue<A>> {
	return do_ { () -> TQueue<A> in
		let read = newTVarIO([A]())
		let write = newTVarIO([A]())
		return TQueue(read, write)
	}
}
