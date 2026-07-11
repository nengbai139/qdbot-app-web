package main

import "testing"

func TestTurnPasswordDeterministic(t *testing.T) {
	a := turnPassword("secret", "1700000000:qdbot")
	b := turnPassword("secret", "1700000000:qdbot")
	if a != b || a == "" {
		t.Fatalf("unexpected password: %q", a)
	}
	if turnPassword("other", "1700000000:qdbot") == a {
		t.Fatal("different secret should differ")
	}
}

func TestBearerToken(t *testing.T) {
	if bearerToken("Bearer abc") != "abc" {
		t.Fatal("parse bearer failed")
	}
	if bearerToken("Basic x") != "" {
		t.Fatal("expected empty")
	}
}
