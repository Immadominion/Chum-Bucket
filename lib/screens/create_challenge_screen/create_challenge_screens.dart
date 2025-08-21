import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/models/models.dart';
import 'package:chumbucket/providers/wallet_provider.dart';
import 'package:chumbucket/screens/challenge_created_screen/challenge_created_screen.dart';
import 'package:chumbucket/screens/create_challenge_screen/widgets/action_button.dart';
import 'package:chumbucket/screens/create_challenge_screen/widgets/bet_amount_step.dart';
import 'package:chumbucket/screens/create_challenge_screen/widgets/description_step.dart';
import 'package:chumbucket/screens/create_challenge_screen/widgets/top_divider.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter a challenge description',
            style: TextStyle(
              fontSize: 18.sp, // Increased font size
              fontWeight: FontWeight.w600, // Increased weight
            ),
          ),
        ),
      );
      return;
    }
    setState(() {
      _currentStep = 1;
    });
  }

  Future<void> _createChallenge() async {
    if (_betAmount <= 0 && _currentStep == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter a valid bet amount',
            style: TextStyle(
              fontSize: 18.sp, // Increased font size
              fontWeight: FontWeight.w600, // Increased weight
            ),
          ),
        ),
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
      final success = await walletProvider.createChallenge(
        friendEmail: widget.friendAddress, 
        friendAddress: widget.friendAddress,
        amount: _betAmount,
        challengeDescription: description,
        durationDays: 7,
      );

      if (mounted) {
        // Replace the pending screen with the appropriate result screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder:
                (context) => ChallengeStateScreen(
                  status:
                      success
                          ? ChallengeStatus.accepted
                          : ChallengeStatus.failed,
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
    } catch (e) {
      if (mounted) {
        // Replace the pending screen with the failed screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder:
                (context) => ChallengeStateScreen(
                  status: ChallengeStatus.failed,
                  errorMessage: e.toString(),
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
    return PopScope(
      canPop: _currentStep == 0,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (_currentStep != 0) {
          // If we're not on the first step, go back to it
          setState(() {
            _currentStep = 0;
          });
        } else {
          Navigator.of(context).maybePop();
        }
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
                          minHeight: MediaQuery.of(context).size.height - 150.h,
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
                                      description: _descriptionController.text,
                                      onBetAmountChanged: (value) {
                                        setState(() {
                                          _betAmount = double.parse(
                                            value.toStringAsFixed(1),
                                          );
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
    );
  }
}
