import 'package:chumbucket/features/challenges/presentation/screens/create_challenge_screen/widgets/action_button.dart';
import 'package:chumbucket/features/challenges/presentation/screens/create_challenge_screen/widgets/description_step.dart';
import 'package:chumbucket/features/challenges/presentation/screens/create_challenge_screen/widgets/top_divider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/shared/models/models.dart';
import 'package:chumbucket/features/wallet/providers/wallet_provider.dart';
import 'package:chumbucket/features/challenges/presentation/screens/challenge_created_screen.dart';
import 'package:chumbucket/features/challenges/presentation/screens/create_challenge_screen/widgets/bet_amount_step.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';

class CreateChallengeScreen extends StatefulWidget {
  final String friendName;
  final String friendAddress;
  final String friendAvatarColor;

  const CreateChallengeScreen({
    super.key,
    required this.friendName,
    required this.friendAddress,
    required this.friendAvatarColor,
  });

  @override
  State<CreateChallengeScreen> createState() => _CreateChallengeScreenState();
}

class _CreateChallengeScreenState extends State<CreateChallengeScreen> {
  double _betAmount = 0.0;
  int _currentStep = 0;
  bool _isCreating = false;
  final TextEditingController _descriptionController = TextEditingController();

  @override
  void dispose() {
    _descriptionController.dispose(); // Add this line
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep == 0 && _descriptionController.text.isEmpty) {
      SnackBarUtils.showError(
        context,
        title: 'Description Required',
        subtitle: 'Please enter a challenge description',
      );
      return;
    }
    setState(() {
      _currentStep = 1;
    });
  }

  Future<void> _createChallenge() async {
    if (_betAmount < 0.05 && _currentStep == 1) {
      SnackBarUtils.showError(
        context,
        title: 'Minimum Bet Required',
        subtitle: 'Minimum bet amount is 0.05 SOL',
      );
      return;
    }

    setState(() {
      _isCreating = true;
    });

    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final description = _descriptionController.text;

    // First navigate to the pending state screen
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) => ChallengeStateScreen(
                status: ChallengeStatus.pending,
                onDone: () {
                  Navigator.pop(context);
                },
              ),
        ),
      );
    }

    try {
      if (kDebugMode) {
        print('🚨 UI: ABOUT TO CALL walletProvider.createChallenge');
        print('🔍 UI: Parameters:');
        print('  - friendEmail: ${widget.friendAddress}');
        print('  - friendAddress: ${widget.friendAddress}');
        print('  - amount: $_betAmount');
        print('  - description: $description');
        print('  - durationDays: 7');
      }

      // Validate friend information before creating challenge
      if (widget.friendAddress.isEmpty) {
        throw Exception(
          'Friend wallet address is not found. Please, delete and add again!',
        );
      }

      final createdChallenge = await walletProvider.createChallenge(
        friendEmail: widget.friendAddress, // Use address as email for now
        friendAddress: widget.friendAddress,
        amount: _betAmount,
        challengeDescription: description,
        durationDays: 7,
        context: context, // Pass context to access AuthProvider
      );

      if (kDebugMode) {
        print(
          '🚨 UI: walletProvider.createChallenge returned: $createdChallenge',
        );
      }

      if (mounted) {
        // Replace the pending screen with the appropriate result screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder:
                (context) => ChallengeStateScreen(
                  status:
                      createdChallenge != null
                          ? ChallengeStatus.accepted
                          : ChallengeStatus.failed,
                  challenge:
                      createdChallenge, // Pass the actual challenge object
                  onDone: () {
                    // Pop back to the previous screen with challenge data
                    Navigator.pop(context);
                    Navigator.pop(context, {
                      'friendName': widget.friendName,
                      'description': description,
                      'amount': _betAmount,
                    });
                  },
                ),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('❌ UI: Exception in challenge creation: $e');
      print('❌ UI: Stack trace: $stackTrace');
      if (mounted) {
        // Replace the pending screen with the failed screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder:
                (context) => ChallengeStateScreen(
                  status: ChallengeStatus.failed,
                  errorMessage: e.toString(),
                  challenge: null, // No challenge created due to error
                  onDone: () {
                    // Pop back to the create challenge screen
                    Navigator.pop(context);
                  },
                ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Debug print constructor parameters
    if (kDebugMode) {
      print('🔍 CreateChallengeScreen initialized with:');
      print('  - friendName: "${widget.friendName}"');
      print('  - friendAddress: "${widget.friendAddress}"');
      print('  - friendAvatarColor: "${widget.friendAvatarColor}"');
    }

    return PopScope(
      canPop: true, // Allow popping
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop && _currentStep != 0) {
          // If we're not on the first step, go back to it
          setState(() {
            _currentStep = 0;
          });
        }
        // If we're on the first step, allow normal navigation
      },
      child: GestureDetector(
        onTap: () {
          // Dismiss keyboard when tapping outside
          FocusScope.of(context).unfocus();
        },
        child: Scaffold(
          backgroundColor: Colors.white,
          resizeToAvoidBottomInset: false,
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    const Center(child: TopDivider()),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        padding: EdgeInsets.only(
                          left: 20.w,
                          right: 20.w,
                          top: 0,
                          bottom: 20.h, // Static padding instead of viewInsets
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight:
                                MediaQuery.of(context).size.height - 150.h,
                          ),
                          child: IntrinsicHeight(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _currentStep == 0
                                    ? Expanded(
                                      flex: 2,
                                      child: ChallengeDescriptionStep(
                                        friendName: widget.friendName,
                                        friendAddress: widget.friendAddress,
                                        friendAvatarColor:
                                            widget.friendAvatarColor,
                                        descriptionController:
                                            _descriptionController, // Add this line
                                      ),
                                    )
                                    : Expanded(
                                      flex: 2,
                                      child: BetAmountStep(
                                        friendName: widget.friendName,
                                        friendAvatarColor:
                                            widget.friendAvatarColor,
                                        betAmount: _betAmount,
                                        description:
                                            _descriptionController.text,
                                        onBetAmountChanged: (value) {
                                          setState(() {
                                            _betAmount = double.parse(
                                              value.toStringAsFixed(3),
                                            );
                                          });
                                        },
                                        onBackPressed: () {
                                          setState(() {
                                            _currentStep = 0;
                                          });
                                        },
                                      ),
                                    ),

                                Expanded(
                                  flex: 1,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      ActionButton(
                                        text:
                                            _currentStep == 0
                                                ? 'Next'
                                                : 'Sign Transaction',
                                        isLoading: _isCreating,
                                        onPressed:
                                            _currentStep == 0
                                                ? _nextStep
                                                : _createChallenge,
                                        isSecondStep:
                                            _currentStep == 1, // Add this line
                                        description:
                                            _descriptionController
                                                .text, // Add this line
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Overlay to handle keyboard overlap
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    color: Colors.white,
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
