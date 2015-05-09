//
//  Exception.swift
//  Concurrent
//
//  Created by Robert Widmann on 2/1/15.
//  Copyright (c) 2015 TypeLift. All rights reserved.
//

import Swiftz

public protocol Exception : Printable {	}

public struct SomeException : Exception {
	public var description : String
	
	init(_ desc : String) {
		self.description = desc
	}
}

public func throw<A>(e : Exception) -> A {
	fatalError(e.description)
}

public func catchException<A>(@autoclosure(escaping) io :  () -> A, handler: Exception -> A) -> A {
	return catch(io, { excn in
		return handler(SomeException(excn.description ?? ""))
	})
}

// TODO: Masked exceptions?
public func mask<A, B>(io : (A -> A) -> B) -> B {
	return io(identity)
}

public func onException<A, B>(@autoclosure(escaping) io :  () -> A, @autoclosure(escaping) what : () -> B) -> A {
	return catchException(io, { e in
		let b : B = what()
		return throw(e)
	})
}

public func bracket<A, B, C>(@autoclosure(escaping) before :  () -> A)(after : A -> B)(thing : A -> C) -> C {
	return mask { (let restore : C -> C) -> C in
		let a = before()
		let r = onException(restore(thing(a)), after(a))
		after(a)
		return r
	}
}

public func finally<A, B>(@autoclosure(escaping) a : () -> A)(@autoclosure(escaping) then :  () -> B) -> A {
	return mask({ (let restore : A -> A) -> A in
		let r = onException(restore(a()), then)
		let b = then()
		return r
	})
}

public func try<A>(@autoclosure(escaping) io :  () -> A) -> Either<Exception, A> {
	return catch(Either.right(io()), Either.left)
}

public func trySome<A, B>(p : Exception -> Optional<B>, @autoclosure(escaping) io :  () -> A) -> Either<B, A> {
	let r = try(io)
	switch r {
	case .Right(let bv):
		return Either.right(bv.value)
	case .Left(let be):
		if let b = p(be.value) {
			return Either.left(b)
		}
		return throw(be.value)
	}
}

private func catch<A>(@autoclosure(escaping) io :  () -> A, handler : Exception -> A) -> A {
	var val : A! 
	CONCRealWorld.catch({ val = io() }, to: { val = handler(SomeException($0.description ?? "")) })
	return val!
}

