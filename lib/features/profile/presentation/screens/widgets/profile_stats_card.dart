// import 'package:flutter/material.dart';
// import 'package:flutter_screenutil/flutter_screenutil.dart';

// /// Stats card showing user activity metrics in the profile
// class ProfileStatsCard extends StatelessWidget {
//   final int completedChallenges;
//   final int totalChallenges;
//   final double winRate;

//   const ProfileStatsCard({
//     super.key,
//     this.completedChallenges = 0,
//     this.totalChallenges = 0,
//     this.winRate = 0.0,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       width: double.infinity,
//       padding: EdgeInsets.all(20.w),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(26.r),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.08),
//             offset: const Offset(0, 2),
//             blurRadius: 8,
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           // Header
//           Text(
//             'Challenge Stats',
//             style: TextStyle(
//               fontSize: 18.sp,
//               fontWeight: FontWeight.w700,
//               color: Colors.black87,
//             ),
//           ),

//           SizedBox(height: 16.h),

//           // Stats row
//           Row(
//             children: [
//               // Completed challenges
//               Expanded(
//                 child: _buildStatItem(
//                   label: 'Completed',
//                   value: completedChallenges.toString(),
//                   color: Colors.green,
//                 ),
//               ),

//               SizedBox(width: 16.w),

//               // Total challenges
//               Expanded(
//                 child: _buildStatItem(
//                   label: 'Total',
//                   value: totalChallenges.toString(),
//                   color: const Color(0xFFFF5A76),
//                 ),
//               ),

//               SizedBox(width: 16.w),

//               // Win rate
//               Expanded(
//                 child: _buildStatItem(
//                   label: 'Win Rate',
//                   value: '${(winRate * 100).toInt()}%',
//                   color: Colors.blue,
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildStatItem({
//     required String label,
//     required String value,
//     required Color color,
//   }) {
//     return Column(
//       children: [
//         Container(
//           padding: EdgeInsets.all(8.w),
//           decoration: BoxDecoration(
//             color: color.withOpacity(0.1),
//             borderRadius: BorderRadius.circular(12.r),
//           ),
//           child: Text(
//             value,
//             style: TextStyle(
//               fontSize: 20.sp,
//               fontWeight: FontWeight.w700,
//               color: color,
//             ),
//           ),
//         ),
//         SizedBox(height: 8.h),
//         Text(
//           label,
//           style: TextStyle(
//             fontSize: 12.sp,
//             color: Colors.grey.shade600,
//             fontWeight: FontWeight.w500,
//           ),
//         ),
//       ],
//     );
//   }
// }
