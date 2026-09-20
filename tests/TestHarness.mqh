#ifndef SMC_TEST_HARNESS_MQH
#define SMC_TEST_HARNESS_MQH

// The local runner injects a unique identifier through a .set file. Tests run
// without broker credentials, market data, DLLs or permission to place trades.
input string SMC_TestRunId = "";

string smc_test_suite = "";
int smc_test_assertions = 0;
int smc_test_failures = 0;
string smc_test_messages[];

string TestJsonEscape(string value)
{
   StringReplace(value, "\\", "\\\\");
   StringReplace(value, "\"", "\\\"");
   StringReplace(value, "\r", "\\r");
   StringReplace(value, "\n", "\\n");
   StringReplace(value, "\t", "\\t");
   return value;
}

void TestAssert(const bool condition, const string label)
{
   smc_test_assertions++;
   if(condition)
      return;
   smc_test_failures++;
   ArrayResize(smc_test_messages, smc_test_failures);
   smc_test_messages[smc_test_failures - 1] = label;
   Print("FAIL ", smc_test_suite, ": ", label);
}

void TestBegin(const string suite)
{
   smc_test_suite = suite;
   smc_test_assertions = 0;
   smc_test_failures = 0;
   ArrayResize(smc_test_messages, 0);
   TestAssert(AccountInfoInteger(ACCOUNT_LOGIN) == 0,
              "fixture terminal has no trading account");
   TestAssert(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED),
              "fixture terminal disallows automated trading");
}

void TestEqual(const long actual, const long expected, const string label)
{
   TestAssert(actual == expected,
              label + " (actual=" + IntegerToString(actual) +
              ", expected=" + IntegerToString(expected) + ")");
}

void TestNear(const double actual, const double expected,
              const double tolerance, const string label)
{
   TestAssert(MathIsValidNumber(actual) && MathIsValidNumber(expected) &&
              tolerance >= 0 && MathAbs(actual - expected) <= tolerance,
              label + " (actual=" + DoubleToString(actual, 10) +
              ", expected=" + DoubleToString(expected, 10) + ")");
}

bool TestFinish()
{
   string report = "{\"run_id\":\"" + TestJsonEscape(SMC_TestRunId) +
                   "\",\"suite\":\"" + TestJsonEscape(smc_test_suite) +
                   "\",\"assertions\":" + IntegerToString(smc_test_assertions) +
                   ",\"failed\":" + IntegerToString(smc_test_failures) +
                   ",\"failures\":[";
   for(int i = 0; i < smc_test_failures; i++)
   {
      if(i > 0)
         report += ",";
      report += "\"" + TestJsonEscape(smc_test_messages[i]) + "\"";
   }
   report += "]}\n";
   const int handle = FileOpen("smc-test-report.json", FILE_WRITE | FILE_TXT | FILE_ANSI, 0, CP_UTF8);
   bool written = false;
   if(handle != INVALID_HANDLE)
   {
      written = FileWriteString(handle, report) > 0;
      FileFlush(handle);
      FileClose(handle);
   }
   Print(smc_test_failures == 0 && written ? "PASS " : "FAIL ",
         smc_test_suite, ": ", smc_test_assertions, " assertions; ",
         smc_test_failures, " failures");
   // Manually running a test must never close the user's terminal.
   if(SMC_TestRunId != "")
      TerminalClose(smc_test_failures == 0 && written ? 0 : 1);
   return smc_test_failures == 0 && written;
}

#endif
