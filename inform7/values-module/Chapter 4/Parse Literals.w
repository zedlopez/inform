[Literals::] Parse Literals.

To decide if an excerpt of text is a value referred to notationally
rather than by name.

@h Literals in the S-grammar.
Most of this section of code defines <s-literal>, the nonterminal which
matches any literal constant. Literal values are explicitly written-out
constants such as "false", "182" or "4:33 PM". Names of objects, rules, and so
on, are also constants, but aren't literal in our sense; on the other hand,
anything which has been defined with a "specifies" sentence ("25 kg specifies
a weight", say) does count as literal. In a natural language, the distinction
is a little blurry, but it's still grammatically useful.

Note that ordinal numbers are not valid as literals: "2nd" is not a noun.

=
<s-literal> ::=
	<cardinal-number> |                    ==> { -, Rvalues::from_int(R[1], W) }
	minus <cardinal-number> |              ==> { -, Rvalues::from_int(-R[1], W) }
	<quoted-text> ( <response-letter> ) |  ==> { -, Rvalues::from_wording(W) }
	<quoted-text> |                        ==> { -, Rvalues::from_wording(W) }
	<s-literal-real-number> |              ==> { pass 1 }
	<s-literal-truth-state> |              ==> { pass 1 }
	<s-literal-list> |                     ==> { pass 1 }
	unicode <s-unicode-character> |        ==> { pass 1 }
	<s-literal-time> |                     ==> { pass 1 }
	<s-literal-unit-notation>              ==> { pass 1 }

<s-literal-unit-notation> internal {
	literal_pattern *lp;
	LOOP_OVER(lp, literal_pattern) {
		int val;
		kind *K = LiteralPatterns::match(lp, W, &val);
		if (K) { ==> { val, Rvalues::from_encoded_notation(K, val, W) }; return TRUE; }
	}
	==> { fail nonterminal };
}

@h Response letters.
Response letters mark certain texts as responses. These are capital letters
A to Z.

=
<response-letter> internal 1 {
	wchar_t *p = Lexer::word_raw_text(Wordings::first_wn(W));
	if ((p) && (p[0] >= 'A') && (p[0] <= 'Z') && (p[1] == 0)) {
		==> { p[0]-'A', - };
		return TRUE;
	}
	==> { fail nonterminal };
}

@h Truth states.
It might seem odd that the truth states count as literals, whereas names of
instances of other kinds (people, say) do not. The argument for this is that
there are always necessarily exactly two truth states, whereas there could
in principle be any number of people, colours, vehicles, and such.

=
<s-literal-truth-state> ::=
	false |  ==> { -, Rvalues::from_boolean(FALSE, W) }
	true     ==> { -, Rvalues::from_boolean(TRUE, W) }

@ The problem message for engineering notation should only appear once:

=
int e_notation_problem_issued = FALSE;

@h Real numbers.
I'm in two minds about whether giving "pi" and "e" special treatment is sensible.
Still:

@d REAL_LITERALS

=
<s-literal-real-number> ::=
	_ pi |                    ==> { -, Rvalues::from_IEEE_754(0x40490FDB, W) }
	_ e |                     ==> { -, Rvalues::from_IEEE_754(0x402DF854, W) }
	plus infinity |           ==> { -, Rvalues::from_IEEE_754(0x7F800000, W) }
	minus infinity |          ==> { -, Rvalues::from_IEEE_754(0xFF800000, W) }
	<literal-real-in-digits>  ==> { -, Rvalues::from_IEEE_754((unsigned int) R[1], W) }

<literal-real-in-digits> internal {
	if ((Wordings::length(W) != 1) && (Wordings::length(W) != 3)) return FALSE;
	wchar_t *p = Lexer::word_raw_text(Wordings::first_wn(W));
	if (p) {
        int expo=0; double intv=0, fracv=0;
		int expocount=0, intcount=0, fraccount=0;
		int signbit = 0;
		int distinctive = FALSE; /* as a floating-point rather than integer number */

		int i = 0;
		@<Parse the sign at the front@>;
		@<Parse any digits into intv@>;
		@<Parse a decimal expansion@>;
		if (intcount + fraccount > 0) {
			if ((Wordings::length(W) > 1) || (p[i])) @<Parse an exponent@>;
			if ((distinctive) || (TEST_COMPILATION_MODE(CONSTANT_CMODE))) {
				==> { Literals::construct_float(signbit, intv, fracv, expo), - };
				return TRUE;
			}
		}
	}
	==> { fail nonterminal };
}

@<Parse the sign at the front@> =
	if (p[i] == '-') { signbit = 1; i++; }
	else if (p[i] == '+') { signbit = 0; i++; }

@<Parse any digits into intv@> =
	while (Characters::isdigit(p[i])) {
		intv = 10.0*intv + (p[i] - '0');
		intcount++;
		i++;
	}

@<Parse a decimal expansion@> =
	if (p[i] == '.') {
		distinctive = TRUE;
		i++;
		double fracpow = 1.0;
		while (Characters::isdigit(p[i])) {
			fracpow *= 0.1;
			fracv = fracv + fracpow*(p[i] - '0');
			fraccount++;
			i++;
		}
	}

@<Parse an exponent@> =
	wchar_t *q = p + i;
	int e_notation_used = FALSE;
	if (Wordings::length(W) > 1) {
		if (q[0] != 0) return FALSE;
		q = Lexer::word_raw_text(Wordings::first_wn(W) + 1);
		if (!((Literals::ismultiplicationsign(q[0])) && (q[1] == 0))) return FALSE;
		q = Lexer::word_raw_text(Wordings::first_wn(W) + 2);
	} else {
		if ((fraccount > 0) && ((q[0] == 'e') || (q[0] == 'E'))) e_notation_used = TRUE;
		else if (!(Literals::ismultiplicationsign(q[0]))) return FALSE;
		q++;
	}
	if (e_notation_used) {
		i = 0;
	} else {
		if (!((q[0] == '1') && (q[1] == '0') && (q[2] == '^'))) return FALSE;
		i = 3;
	}
	int exposign = 0;
	if (q[i] == '+') i++; else if (q[i] == '-') { exposign = 1; i++; }
	while (Characters::isdigit(q[i])) {
		expo = 10*expo + (q[i] - '0');
		expocount++;
		i++;
	}
	if (q[i]) return FALSE;
	if (expocount == 0) return FALSE;
	if (exposign) { expo = -expo; }
	distinctive = TRUE;
	if ((e_notation_used) && (global_compilation_settings.allow_engineering_notation == FALSE) &&
		(e_notation_problem_issued == FALSE)) {
		e_notation_problem_issued = TRUE;
		Problems::quote_source(1, current_sentence);
		Problems::quote_wording(2, W);
		StandardProblems::handmade_problem(Task::syntax_tree(), _p_(PM_WantonEngineering));
		Problems::issue_problem_segment(
			"In %1, you write '%2', which looks to me like the engineering "
			"notation for a real number - I'm guessing that the 'e' means "
			"exponent, so for example, 1E+6 means 1000000. Inform writes "
			"numbers like this as 1 x 10^6, or if you prefer 1.0 x 10^6; "
			"or you can use a multiplication sign instead of the 'x'.");
		Problems::issue_problem_end();
	}

@ =
int Literals::ismultiplicationsign(int c) {
	if ((c == 'x') || (c == '*')) return TRUE;
	return FALSE;
}

@ The following routine, adapted from code contributed to I6 by Andrew
Plotkin, returns the IEEE-754 single-precision encoding of a floating-point
number. See:
= (text)
	http://www.psc.edu/general/software/packages/ieee/ieee.php
=
for an explanation.

If the magnitude is too large (beyond about |3.4e+38|), this returns plus or
minus infinity; if the magnitude is too small (below about |1e-45|), this returns
a zero value. If any of the inputs are NaN, this returns NaN.

=
int Literals::construct_float(int signbit, double intv, double fracv, int expo) {
	double absval = (intv + fracv) * Literals::ten_to_the(expo);
	int sign = (signbit ? ((int) 0x80000000) : 0x0);

	latest_constructed_real = absval; if (signbit) latest_constructed_real = -absval;

	if (isinf(absval)) @<Return plus or minus infinity@>;
	if (isnan(absval)) @<Return plus or minus Not-a-Number@>;

	double mant = frexp(absval, &expo);
	@<Normalize mantissa to be in the range [1.0, 2.0)@>;

	if (expo >= 128) @<Return plus or minus infinity@>;
	if (expo < -126) @<Denormalize this very small number@>
	else if (!(expo == 0 && mant == 0.0)) @<Denormalize this non-zero number@>;

	int fbits = 0;
	@<Set fbits to the mantissa times 2 to the 23, rounded to the nearest integer@>;

	return (sign) | ((int)(expo << 23)) | (fbits);
}

@<Normalize mantissa to be in the range [1.0, 2.0)@> =
	if ((0.5 <= mant) && (mant < 1.0)) {
		mant *= 2.0;
		expo--;
	} else if (mant == 0.0) {
		expo = 0;
	} else @<Return plus or minus infinity@>;

@ One of the following two things then happens, resulting in the exponent
now being in the range 0 to 255, and the mantissa in [0, 1).

@<Denormalize this very small number@> =
	mant = ldexp(mant, 126 + expo);
	expo = 0; /* 0 now represents 10 to the minus 127 */

@<Denormalize this non-zero number@> =
	expo += 127; /* 127 now represents 10 to the 0, that is, 1 */
	mant -= 1.0; /* the mantissa was in the range [1, 2), is now in [0, 1) */

@ At this point the mantissa is a number in the range [0, 1), so multiplying
it by 2 to the 23 will produce the bottom 22 bits of our answer. The case
we have to be wary of is where the carry propagates out of a string of 23
1 bits, that is, where we end up with bit 23 set as well: in that case, the
exponent increments, and we round to that power of 10 exactly.

Note that 2 to the 23 is 8388608.

@<Set fbits to the mantissa times 2 to the 23, rounded to the nearest integer@> =
	fbits = (int) ((mant*8388608.0) + 0.5); /* round to nearest integer */
	if (fbits >> 23) {
		fbits = 0;
		expo++; if (expo >= 255) @<Return plus or minus infinity@>;
	}

@<Return plus or minus infinity@> =
	return sign | 0x7f800000;

@<Return plus or minus Not-a-Number@> =
	return sign | 0x7fc00000;

@ The following returns 10 to the given power.

@d POW10_RANGE 8

=
double Literals::ten_to_the(int expo) {
	static double powers[POW10_RANGE*2+1] = {
		0.00000001, 0.0000001, 0.000001, 0.00001, 0.0001, 0.001, 0.01, 0.1,
		1.0,
		10.0, 100.0, 1000.0, 10000.0, 100000.0, 1000000.0, 10000000.0, 100000000.0
	};

	double res = 1.0;

	if (expo < 0)
		for (; expo < -POW10_RANGE; expo += POW10_RANGE)
			res *= powers[0];
	else
		for (; expo > POW10_RANGE; expo -= POW10_RANGE)
			res *= powers[POW10_RANGE*2];

	return res * powers[POW10_RANGE+expo];
}